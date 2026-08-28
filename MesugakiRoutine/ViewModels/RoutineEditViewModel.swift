import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RoutineEditViewModel {
    private(set) var routine: Routine?
    var title: String = ""
    var type: RoutineType = .custom
    /// 開始予定時間。サボり通知はこの時刻を起点に計算されるため、新規作成時もデフォルト値を持たせる。
    var scheduledStartTime: Date = Routine.date(fromMinutes: 8 * 60)
    /// 対象曜日。デフォルトは全曜日選択。
    var selectedWeekdays: Set<Int> = Set(Weekday.allWeekdayValues)
    private(set) var steps: [RoutineStep] = []
    var newStepTitle: String = ""

    private var dependencies: AppDependencies?

    init(routine: Routine?) {
        self.routine = routine
        if let routine {
            title = routine.title
            type = routine.type
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

    /// 1日でも対象曜日から外れていたら、毎日継続することを勧めるヒントを出す。
    var showEveryDayHint: Bool {
        selectedWeekdays.count < Weekday.allCases.count
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
        if let routine {
            steps = routine.orderedSteps
        }
    }

    /// タイトル・種別などを保存する。新規作成の場合はここでルーティンを作成する。
    func save() {
        guard let dependencies, canSave else { return }
        let scheduledStartMinute = Routine.minutes(from: scheduledStartTime)
        let weekdayValues = Array(selectedWeekdays)
        if let routine {
            dependencies.routineRepository.update(
                routine, title: title, type: type, isActive: routine.isActive,
                scheduledStartMinute: scheduledStartMinute, activeWeekdayValues: weekdayValues
            )
        } else {
            let created = dependencies.routineRepository.create(
                title: title, type: type,
                scheduledStartMinute: scheduledStartMinute, activeWeekdayValues: weekdayValues
            )
            routine = created
        }
    }

    func addStep() {
        let trimmed = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let dependencies else { return }
        if routine == nil { save() }
        guard let routine else { return }
        dependencies.routineRepository.addStep(
            to: routine, title: trimmed, description: "", estimatedMinutes: 2, isRequired: true
        )
        steps = routine.orderedSteps
        newStepTitle = ""
    }

    func deleteSteps(at offsets: IndexSet) {
        guard let dependencies, let routine else { return }
        for index in offsets {
            dependencies.routineRepository.deleteStep(steps[index], from: routine)
        }
        steps = routine.orderedSteps
    }

    func renameStep(_ step: RoutineStep, newTitle: String) {
        guard let dependencies else { return }
        dependencies.routineRepository.updateStep(
            step, title: newTitle, description: step.stepDescription,
            estimatedMinutes: step.estimatedMinutes, isRequired: step.isRequired
        )
        if let routine { steps = routine.orderedSteps }
    }

    func moveSteps(from source: IndexSet, to destination: Int) {
        guard let dependencies, let routine else { return }
        var reordered = steps
        reordered.move(fromOffsets: source, toOffset: destination)
        dependencies.routineRepository.reorderSteps(of: routine, orderedIds: reordered.map(\.id))
        steps = routine.orderedSteps
    }
}
