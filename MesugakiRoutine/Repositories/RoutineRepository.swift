import Foundation
import SwiftData

/// Routine / RoutineStep の永続化を担当する。SwiftData の ModelContext を薄くラップする。
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

    func fetch(type: RoutineType) -> [Routine] {
        fetchAll().filter { $0.type == type && $0.isActive }
    }

    @discardableResult
    func create(
        title: String,
        type: RoutineType,
        scheduledStartMinute: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues
    ) -> Routine {
        let routine = Routine(
            title: title, type: type,
            scheduledStartMinute: scheduledStartMinute, activeWeekdayValues: activeWeekdayValues
        )
        context.insert(routine)
        save()
        return routine
    }

    func update(
        _ routine: Routine,
        title: String,
        type: RoutineType,
        isActive: Bool,
        scheduledStartMinute: Int?,
        activeWeekdayValues: [Int]
    ) {
        routine.title = title
        routine.type = type
        routine.isActive = isActive
        routine.scheduledStartMinute = scheduledStartMinute
        routine.activeWeekdayValues = activeWeekdayValues
        routine.updatedAt = .now
        save()
    }

    func delete(_ routine: Routine) {
        context.delete(routine)
        save()
    }

    @discardableResult
    func addStep(to routine: Routine, title: String, description: String, estimatedMinutes: Int, isRequired: Bool) -> RoutineStep {
        let nextIndex = (routine.steps.map(\.orderIndex).max() ?? -1) + 1
        let step = RoutineStep(
            title: title,
            stepDescription: description,
            orderIndex: nextIndex,
            estimatedMinutes: estimatedMinutes,
            isRequired: isRequired,
            routine: routine
        )
        context.insert(step)
        routine.updatedAt = .now
        save()
        return step
    }

    func updateStep(_ step: RoutineStep, title: String, description: String, estimatedMinutes: Int, isRequired: Bool) {
        step.title = title
        step.stepDescription = description
        step.estimatedMinutes = estimatedMinutes
        step.isRequired = isRequired
        step.updatedAt = .now
        save()
    }

    func deleteStep(_ step: RoutineStep, from routine: Routine) {
        context.delete(step)
        reindexSteps(of: routine)
        save()
    }

    /// ステップの並び順を `orderedIds` の並びに従って更新する。
    func reorderSteps(of routine: Routine, orderedIds: [UUID]) {
        for (index, stepId) in orderedIds.enumerated() {
            if let step = routine.steps.first(where: { $0.id == stepId }) {
                step.orderIndex = index
            }
        }
        routine.updatedAt = .now
        save()
    }

    private func reindexSteps(of routine: Routine) {
        for (index, step) in routine.orderedSteps.enumerated() {
            step.orderIndex = index
        }
    }

    private func save() {
        try? context.save()
    }
}
