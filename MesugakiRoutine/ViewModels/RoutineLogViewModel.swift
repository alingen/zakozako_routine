import Foundation
import SwiftData
import Observation

/// 1つのルーティンの直近30日ぶんの達成率。対象曜日(activeWeekdayValues)に該当する日だけを分母に数える。
struct RoutineAchievement: Identifiable {
    let routine: Routine
    let completedCount: Int
    let applicableCount: Int

    var id: UUID { routine.id }
    var rate: Double { applicableCount == 0 ? 0 : Double(completedCount) / Double(applicableCount) }
}

@Observable
@MainActor
final class RoutineLogViewModel {
    private(set) var routines: [Routine] = []
    /// 日(startOfDay) → その日に完了したルーティンのid集合。
    private(set) var completionsByDay: [Date: Set<UUID>] = [:]
    /// 直近30日の、ルーティンごとの達成率。
    private(set) var achievements: [RoutineAchievement] = []
    /// 今日(または昨日まで)を含めて何日連続でいずれかのルーティンを達成しているか。
    private(set) var streakDays: Int = 0
    var displayedMonth: Date

    private var dependencies: AppDependencies?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.displayedMonth = Self.startOfMonth(for: .now, calendar: calendar)
    }

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        // 朝/夜という分類は使わず、開始予定時刻→作成日順の中立な並びにする。
        routines = dependencies.routineRepository.fetchAll().sorted { lhs, rhs in
            switch (lhs.scheduledStartMinute, rhs.scheduledStartMinute) {
            case let (l?, r?): return l != r ? l < r : lhs.createdAt < rhs.createdAt
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            }
        }

        let sessions = dependencies.sessionRepository.fetchAllSessions()

        var map: [Date: Set<UUID>] = [:]
        for session in sessions where session.status == .completed {
            guard let completedAt = session.completedAt else { continue }
            let day = calendar.startOfDay(for: completedAt)
            map[day, default: []].insert(session.routineId)
        }
        completionsByDay = map

        achievements = computeAchievements(sessions: sessions)
        streakDays = StreakCalculator.currentStreak(sessions: sessions, calendar: calendar)
    }

    /// 直近30日(今日を含む)ぶんの、アクティブなルーティンごとの達成率を計算する。
    /// 対象曜日に該当しない日や、ルーティン作成日より前の日は分母に含めない。
    private func computeAchievements(sessions: [RoutineSession], now: Date = .now, windowDays: Int = 30) -> [RoutineAchievement] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else { return [] }

        return routines.filter(\.isActive).map { routine in
            let createdDay = calendar.startOfDay(for: routine.createdAt)
            let rangeStart = max(windowStart, createdDay)
            let completedDays = Set(
                sessions.filter { $0.routineId == routine.id && $0.status == .completed }
                    .compactMap { $0.completedAt }
                    .map { calendar.startOfDay(for: $0) }
            )

            var applicableCount = 0
            var completedCount = 0
            var cursor = rangeStart
            while cursor <= today {
                let weekday = calendar.component(.weekday, from: cursor)
                if routine.activeWeekdayValues.contains(weekday) {
                    applicableCount += 1
                    if completedDays.contains(cursor) { completedCount += 1 }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return RoutineAchievement(routine: routine, completedCount: completedCount, applicableCount: applicableCount)
        }
    }

    func goToPreviousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }

    func goToNextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }

    /// 表示月のカレンダーグリッド用の日付配列。週の頭を揃えるための前後の余白は nil。
    func daysInDisplayedMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }

        let weekdayOfFirst = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyCount = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyCount)
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    /// カレンダーの曜日ヘッダー(ロケールの週の始まりに合わせて並び替え済み)。
    var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    func completedRoutines(on day: Date) -> [Routine] {
        let key = calendar.startOfDay(for: day)
        guard let ids = completionsByDay[key] else { return [] }
        return routines.filter { ids.contains($0.id) }
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}
