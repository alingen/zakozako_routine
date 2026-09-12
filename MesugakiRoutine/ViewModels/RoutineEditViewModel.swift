import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RoutineEditViewModel {
    private(set) var routine: Routine?
    var title: String = ""
    /// 円の中に表示するアイコン(SF Symbol 名)。未選択なら nil。
    var iconName: String?
    /// 集計期間(1日 / 1週間のうち / 1ヶ月のうち)。
    var period: HabitPeriod = .day
    /// 期間あたりの目標回数。デフォルト1。
    var targetCount: Int = 1
    /// 開始予定時間。通知の起点。
    var scheduledStartTime: Date = Routine.date(fromMinutes: 8 * 60)
    var notifyAtScheduledTime: Bool = false
    /// 対象曜日。period == .day のときだけ有効。デフォルトは全曜日。
    var selectedWeekdays: Set<Int> = Set(Weekday.allWeekdayValues)
    private(set) var saveErrorMessage: String?

    private var dependencies: AppDependencies?

    init(routine: Routine?) {
        self.routine = routine
        if let routine {
            title = routine.title
            iconName = routine.iconName
            period = routine.period
            targetCount = routine.targetCount
            notifyAtScheduledTime = routine.scheduledStartMinute != nil
            if let minute = routine.scheduledStartMinute {
                scheduledStartTime = Routine.date(fromMinutes: minute)
            }
            if !routine.activeWeekdayValues.isEmpty {
                selectedWeekdays = Set(routine.activeWeekdayValues)
            }
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 対象曜日を選べるか(1日の期間のときだけ)。
    var canSelectWeekdays: Bool { period.supportsWeekdaySelection }

    /// 1日でも対象曜日から外れていたら、毎日やることを勧めるヒントを出す。
    var showEveryDayHint: Bool {
        canSelectWeekdays && selectedWeekdays.count < Weekday.allCases.count
    }

    func toggleWeekday(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday.rawValue) {
            selectedWeekdays.remove(weekday.rawValue)
        } else {
            selectedWeekdays.insert(weekday.rawValue)
        }
    }

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
    }

    /// 変更を保存する。新規作成の場合はここで約束を作成する。
    @discardableResult
    func save() -> Bool {
        guard let dependencies, canSave else { return false }
        let scheduledStartMinute = notifyAtScheduledTime ? Routine.minutes(from: scheduledStartTime) : nil
        // 週/月の期間では対象曜日は全曜日扱いにする。
        let weekdayValues = canSelectWeekdays ? Array(selectedWeekdays) : Weekday.allWeekdayValues
        let count = max(targetCount, 1)

        do {
            if let routine {
                try dependencies.routineRepository.update(
                    routine,
                    title: title,
                    isActive: routine.isActive,
                    iconName: iconName,
                    period: period,
                    targetCount: count,
                    scheduledStartMinute: scheduledStartMinute,
                    activeWeekdayValues: weekdayValues
                )
            } else {
                routine = try dependencies.routineRepository.create(
                    title: title,
                    iconName: iconName,
                    period: period,
                    targetCount: count,
                    scheduledStartMinute: scheduledStartMinute,
                    activeWeekdayValues: weekdayValues
                )
            }
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    func clearSaveError() {
        saveErrorMessage = nil
    }

    /// この約束を削除する(既存の編集時のみ)。
    @discardableResult
    func deleteRoutine() -> Bool {
        guard let dependencies, let routine else { return false }
        do {
            try dependencies.routineRepository.delete(routine)
            saveErrorMessage = nil
            self.routine = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
