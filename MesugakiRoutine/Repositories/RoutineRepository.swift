import Foundation
import SwiftData

/// Routine の永続化を担当する。
@MainActor
final class RoutineRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [Routine] {
        let descriptor = FetchDescriptor<Routine>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetch(id: UUID) -> Routine? {
        fetchAll().first { $0.id == id }
    }

    @discardableResult
    func create(
        title: String,
        iconName: String? = nil,
        period: HabitPeriod = .day,
        targetCount: Int = 1,
        scheduledStartMinute: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues
    ) throws -> Routine {
        let routine = Routine(
            title: title,
            scheduledStartMinute: scheduledStartMinute,
            activeWeekdayValues: activeWeekdayValues,
            iconName: iconName,
            period: period,
            targetCount: targetCount
        )
        try performMutation {
            context.insert(routine)
        }
        return routine
    }

    func update(
        _ routine: Routine,
        title: String,
        isActive: Bool,
        iconName: String?,
        period: HabitPeriod,
        targetCount: Int,
        scheduledStartMinute: Int?,
        activeWeekdayValues: [Int],
        now: Date = .now
    ) throws {
        let periodChanged = routine.period != period
        let targetChanged = routine.targetCount != max(targetCount, 1)
        let currentWeekdays = normalizedWeekdays(routine.activeWeekdayValues)
        let updatedWeekdays = normalizedWeekdays(activeWeekdayValues)
        let weekdaysChanged = routine.period == .day
            && period == .day
            && currentWeekdays != updatedWeekdays

        try performMutation {
            // 現在のルールを過去ログへ遡及適用すると統計が書き換わってしまうため、
            // 集計ルールが変わった時点から新しい統計区間として扱う。
            if periodChanged || targetChanged || weekdaysChanged {
                try RoutineYearStatisticsCalculator.archiveCurrentRule(
                    for: routine,
                    until: now
                )
                routine.currentRuleStartedAt = now
            }

            routine.title = title
            routine.isActive = isActive
            routine.iconName = iconName
            routine.period = period
            routine.targetCount = targetCount
            routine.scheduledStartMinute = scheduledStartMinute
            routine.activeWeekdayValues = activeWeekdayValues
            routine.updatedAt = now
        }
    }

    func delete(_ routine: Routine) throws {
        try performMutation {
            context.delete(routine)
        }
    }

    /// 「1回やった」を記録する。
    func recordProgress(_ routine: Routine, now: Date = .now) throws {
        try performMutation {
            routine.progressEvents.append(now)
            routine.updatedAt = now
        }
    }

    // MARK: - デバッグ用

    /// 指定日の正午に進捗イベントを1件入れる(連続達成日数の確認用)。
    func debugInsertProgress(
        _ routine: Routine,
        on day: Date,
        calendar: Calendar = .current
    ) throws {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        try performMutation {
            if routine.progressStatisticsArchiveData == nil {
                routine.currentRuleStartedAt = min(routine.currentRuleStartedAt, noon)
            }
            routine.progressEvents.append(noon)
        }
    }

    private func performMutation(_ mutation: () throws -> Void) throws {
        do {
            try context.transaction {
                try mutation()
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func normalizedWeekdays(_ values: [Int]) -> Set<Int> {
        values.isEmpty ? Set(Weekday.allWeekdayValues) : Set(values)
    }
}
