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
    ) -> Routine {
        let routine = Routine(
            title: title,
            scheduledStartMinute: scheduledStartMinute,
            activeWeekdayValues: activeWeekdayValues,
            iconName: iconName,
            period: period,
            targetCount: targetCount
        )
        context.insert(routine)
        save()
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
        activeWeekdayValues: [Int]
    ) {
        routine.title = title
        routine.isActive = isActive
        routine.iconName = iconName
        routine.period = period
        routine.targetCount = targetCount
        routine.scheduledStartMinute = scheduledStartMinute
        routine.activeWeekdayValues = activeWeekdayValues
        routine.updatedAt = .now
        save()
    }

    func delete(_ routine: Routine) {
        context.delete(routine)
        save()
    }

    /// 「1回やった」を記録する。
    func recordProgress(_ routine: Routine, now: Date = .now, calendar: Calendar = .current) {
        routine.progressEvents.append(now)
        // 判定に不要な古いイベントは捨てる(直近3か月より前)。
        if let cutoff = calendar.date(byAdding: .month, value: -3, to: now) {
            routine.progressEvents.removeAll { $0 < cutoff }
        }
        routine.updatedAt = now
        save()
    }

    /// 直近の「1回やった」を1件取り消す(誤タップのundo用)。
    func undoLastProgress(_ routine: Routine) {
        guard !routine.progressEvents.isEmpty else { return }
        var events = routine.progressEvents
        events.removeLast()
        routine.progressEvents = events
        routine.updatedAt = .now
        save()
    }

    // MARK: - デバッグ用

    /// 指定日の正午に進捗イベントを1件入れる(連続達成日数の確認用)。
    func debugInsertProgress(_ routine: Routine, on day: Date, calendar: Calendar = .current) {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        routine.progressEvents.append(noon)
        save()
    }

    private func save() {
        try? context.save()
    }
}
