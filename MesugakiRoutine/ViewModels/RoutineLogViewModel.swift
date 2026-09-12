import Foundation
import SwiftData
import Observation

/// 1つの約束の直近30暦日ぶんの達成率。日／週／月はそれぞれ期間を1機会として数える。
struct RoutineAchievement: Identifiable {
    let routine: Routine
    let completedCount: Int
    let applicableCount: Int
    let unitLabel: String

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
    private(set) var hasLoaded = false
    var displayedMonth: Date

    private var dependencies: AppDependencies?
    private var completionDatesByRoutineID: [UUID: [Date]] = [:]
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.displayedMonth = Self.startOfMonth(
            for: AppDay.anchor(.now, calendar: calendar),
            calendar: calendar
        )
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
        completionDatesByRoutineID = Dictionary(
            uniqueKeysWithValues: routines.map { routine in
                (
                    routine.id,
                    RoutineYearStatisticsCalculator.completionDates(
                        for: routine,
                        now: now,
                        calendar: calendar
                    )
                )
            }
        )
        rebuildDisplayedMonthCompletions()
        achievements = computeAchievements(now: now)
        streakDays = RoutineStreak.overallStreak(
            completionDates: completionDatesByRoutineID.values.flatMap { $0 },
            now: now,
            calendar: calendar
        )
        hasLoaded = true
    }

    private func computeAchievements(now: Date, windowDays: Int = 30) -> [RoutineAchievement] {
        return routines.filter(\.isActive).map { routine in
            let summary = RoutineYearStatisticsCalculator.recentSummary(
                for: routine,
                trailingCalendarDays: windowDays,
                now: now,
                calendar: calendar
            )
            return RoutineAchievement(
                routine: routine,
                completedCount: summary.completedCount,
                applicableCount: summary.applicableCount,
                unitLabel: summary.unitLabel
            )
        }
    }

    func goToPreviousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = newMonth
        rebuildDisplayedMonthCompletions()
    }

    func goToNextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = newMonth
        rebuildDisplayedMonthCompletions()
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

    private func rebuildDisplayedMonthCompletions() {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            completionsByDay = [:]
            return
        }

        var map: [Date: Set<UUID>] = [:]
        for routine in routines {
            let completionDates = completionDatesByRoutineID[routine.id] ?? []
            for completedAt in completionDates {
                let completedCalendarDay = calendar.startOfDay(
                    for: AppDay.anchor(completedAt, calendar: calendar)
                )
                if completedCalendarDay >= monthInterval.start,
                   completedCalendarDay < monthInterval.end {
                    map[completedCalendarDay, default: []].insert(routine.id)
                }
            }
        }
        completionsByDay = map
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}
