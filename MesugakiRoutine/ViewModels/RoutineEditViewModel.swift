import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RoutineEditViewModel {
    private(set) var routine: Routine?
    var title: String = ""
    var description: String = ""
    var type: RoutineType = .custom
    private(set) var steps: [RoutineStep] = []
    var newStepTitle: String = ""

    private var dependencies: AppDependencies?

    init(routine: Routine?) {
        self.routine = routine
        if let routine {
            title = routine.title
            description = routine.routineDescription
            type = routine.type
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        if let routine {
            steps = routine.orderedSteps
        }
    }

    /// タイトル・種別・説明を保存する。新規作成の場合はここでルーティンを作成する。
    func save() {
        guard let dependencies, canSave else { return }
        if let routine {
            dependencies.routineRepository.update(
                routine, title: title, description: description, type: type, isActive: routine.isActive
            )
        } else {
            let created = dependencies.routineRepository.create(title: title, description: description, type: type)
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
