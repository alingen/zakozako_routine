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
        cueText: String? = nil,
        iconName: String? = nil,
        period: HabitPeriod = .day,
        targetCount: Int = 1,
        scheduledStartMinute: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues,
        targetDurationMinutes: Int? = nil,
        shareToZakoNews: Bool = false
    ) throws -> Routine {
        let routine = Routine(
            title: title,
            cueText: normalizedCueText(cueText),
            scheduledStartMinute: scheduledStartMinute,
            targetDurationMinutes: targetDurationMinutes,
            activeWeekdayValues: activeWeekdayValues,
            iconName: iconName,
            period: period,
            targetCount: targetCount
        )
        try performMutation {
            routine.shareToZakoNews = shareToZakoNews
            context.insert(routine)
        }
        return routine
    }

    func update(
        _ routine: Routine,
        title: String,
        cueText: String?,
        isActive: Bool,
        iconName: String?,
        period: HabitPeriod,
        targetCount: Int,
        scheduledStartMinute: Int?,
        activeWeekdayValues: [Int],
        targetDurationMinutes: Int? = nil,
        now: Date = .now,
        shareToZakoNews: Bool? = nil
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
                routine.homeCompletionRecordedAt = nil
                routine.homeCompletionAddedCount = nil
            }

            routine.title = title
            if let shareToZakoNews { routine.shareToZakoNews = shareToZakoNews }
            routine.cueText = normalizedCueText(cueText)
            routine.isActive = isActive
            routine.iconName = iconName
            routine.period = period
            routine.targetCount = targetCount
            routine.scheduledStartMinute = scheduledStartMinute
            routine.activeWeekdayValues = activeWeekdayValues
            routine.targetDurationMinutes = targetDurationMinutes.map { max($0, 1) }
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

    /// 現在の集計期間を、チェックボックス操作に合わせて完了／未完了へ切り替える。
    ///
    /// 複数回目標では、完了時は不足分だけを補い、その補完数を保存する。
    /// 解除時は補ったログを優先して除くため、タップ前に途中まで実行していた回数へ戻せる。
    /// タイマー等で達成した場合は、現在期間の最新ログから未達成になる件数まで戻す。
    func setCompletion(
        _ routine: Routine,
        completed: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let window = routine.period.window(containing: now, calendar: calendar)
        let lowerBound = max(window.start, routine.currentRuleStartedAt)
        let currentEventIndices = routine.progressEvents.indices.filter { index in
            let event = routine.progressEvents[index]
            return event >= lowerBound && event < window.end && event <= now
        }

        if completed {
            let missingCount = max(routine.targetCount - currentEventIndices.count, 0)
            guard missingCount > 0 else { return }

            try performMutation {
                routine.progressEvents.append(contentsOf: Array(repeating: now, count: missingCount))
                routine.homeCompletionRecordedAt = now
                routine.homeCompletionAddedCount = missingCount
                routine.updatedAt = now
            }
            return
        }

        var indicesToRemove = Set<Int>()
        if let recordedAt = routine.homeCompletionRecordedAt,
           let addedCount = routine.homeCompletionAddedCount,
           addedCount > 0,
           recordedAt >= lowerBound,
           recordedAt < window.end {
            indicesToRemove.formUnion(
                currentEventIndices
                    .filter { routine.progressEvents[$0] == recordedAt }
                    .sorted(by: >)
                    .prefix(addedCount)
            )
        }

        // マーカーのない旧データや、補完後に別ログが増えた場合でも、確実に未達成へ戻す。
        let remainingCount = currentEventIndices.count - indicesToRemove.count
        let retainedCount = max(routine.targetCount - 1, 0)
        let additionalRemovalCount = max(remainingCount - retainedCount, 0)
        if additionalRemovalCount > 0 {
            indicesToRemove.formUnion(
                currentEventIndices
                    .filter { !indicesToRemove.contains($0) }
                    .sorted { lhs, rhs in
                        let leftDate = routine.progressEvents[lhs]
                        let rightDate = routine.progressEvents[rhs]
                        if leftDate == rightDate { return lhs > rhs }
                        return leftDate > rightDate
                    }
                    .prefix(additionalRemovalCount)
            )
        }

        guard !indicesToRemove.isEmpty else { return }

        try performMutation {
            routine.progressEvents = routine.progressEvents.enumerated().compactMap { index, event in
                indicesToRemove.contains(index) ? nil : event
            }
            routine.homeCompletionRecordedAt = nil
            routine.homeCompletionAddedCount = nil
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

    private func normalizedCueText(_ cueText: String?) -> String? {
        let trimmed = cueText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
