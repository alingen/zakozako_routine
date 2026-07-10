import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RoutineLogViewModel {
    private(set) var routines: [Routine] = []
    /// 日(startOfDay) → その日に完了したルーティンのid集合。
    private(set) var completionsByDay: [Date: Set<UUID>] = [:]
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
        routines = dependencies.routineRepository.fetchAll()
            .sorted { sortOrder(for: $0.type) < sortOrder(for: $1.type) }

        var map: [Date: Set<UUID>] = [:]
        for session in dependencies.sessionRepository.fetchAllSessions() where session.status == .completed {
            guard let completedAt = session.completedAt else { continue }
            let day = calendar.startOfDay(for: completedAt)
            map[day, default: []].insert(session.routineId)
        }
        completionsByDay = map
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

    private func sortOrder(for type: RoutineType) -> Int {
        switch type {
        case .morning: return 0
        case .night: return 1
        case .custom: return 2
        }
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}
