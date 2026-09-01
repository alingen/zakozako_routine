import Foundation
import SwiftData
import Observation

/// 1つの約束の直近30日ぶんの達成率。「対象日(1日なら対象曜日、週/月は全日)」を分母に数える。
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
    /// 日(startOfDay) → その日に達成した約束のid集合。
    private(set) var completionsByDay: [Date: Set<UUID>] = [:]
    private(set) var achievements: [RoutineAchievement] = []
    /// いずれかの約束を達成した日が今日(または昨日)から連続している数。
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
        routines = dependencies.routineRepository.fetchAll().sorted { lhs, rhs in
            switch (lhs.scheduledStartMinute, rhs.scheduledStartMinute) {
            case let (l?, r?): return l != r ? l < r : lhs.createdAt < rhs.createdAt
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            }
        }

        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -120, to: today) else { return }

        var map: [Date: Set<UUID>] = [:]
        var cursor = windowStart
        while cursor <= today {
            for routine in routines where routine.wasCompleteOn(day: cursor, now: now, calendar: calendar) {
                map[cursor, default: []].insert(routine.id)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        completionsByDay = map

        achievements = computeAchievements(now: now)
        streakDays = RoutineStreak.overallStreak(routines: routines, now: now, calendar: calendar)
    }

    private func computeAchievements(now: Date, windowDays: Int = 30) -> [RoutineAchievement] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) else { return [] }

        return routines.filter(\.isActive).map { routine in
            let createdDay = calendar.startOfDay(for: routine.createdAt)
            let rangeStart = max(windowStart, createdDay)

            var applicable = 0
            var completed = 0
            var cursor = rangeStart
            while cursor <= today {
                if routine.isScheduled(on: cursor, calendar: calendar) {
                    applicable += 1
                    if routine.wasCompleteOn(day: cursor, now: now, calendar: calendar) { completed += 1 }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return RoutineAchievement(routine: routine, completedCount: completed, applicableCount: applicable)
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
