import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class BlockedBehaviorListViewModel {
    private(set) var behaviors: [BlockedBehavior] = []

    var newTitle: String = ""
    var newTriggerText: String = ""
    var newCounterMessage: String = ""

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        behaviors = dependencies.blockedBehaviorRepository.fetchAll()
    }

    var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func add() {
        guard let dependencies, canAdd else { return }
        dependencies.blockedBehaviorRepository.create(
            title: newTitle,
            description: "",
            triggerText: newTriggerText,
            counterMessage: newCounterMessage
        )
        newTitle = ""
        newTriggerText = ""
        newCounterMessage = ""
        reload()
    }

    func delete(at offsets: IndexSet) {
        guard let dependencies else { return }
        for index in offsets {
            dependencies.blockedBehaviorRepository.delete(behaviors[index])
        }
        reload()
    }

    func toggleActive(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.update(
            behavior,
            title: behavior.title,
            description: behavior.behaviorDescription,
            triggerText: behavior.triggerText,
            counterMessage: behavior.counterMessage,
            isActive: !behavior.isActive
        )
        reload()
    }
}
