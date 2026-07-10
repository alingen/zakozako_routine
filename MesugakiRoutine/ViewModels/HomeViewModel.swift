import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    private(set) var morningRoutine: Routine?
    private(set) var nightRoutine: Routine?
    private(set) var blockedBehaviors: [BlockedBehavior] = []
    var newBlockedBehaviorTitle: String = ""

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        morningRoutine = dependencies.routineRepository.fetch(type: .morning).first
        nightRoutine = dependencies.routineRepository.fetch(type: .night).first
        blockedBehaviors = dependencies.blockedBehaviorRepository.fetchAll()
    }

    func addBlockedBehavior() {
        guard let dependencies else { return }
        let trimmed = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dependencies.blockedBehaviorRepository.create(
            title: trimmed,
            description: "",
            triggerText: trimmed,
            counterMessage: ""
        )
        newBlockedBehaviorTitle = ""
        reload()
    }

    func toggleBlockedBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.setActive(behavior, isActive: !behavior.isActive)
        reload()
    }

    func deleteBlockedBehaviors(at offsets: IndexSet) {
        guard let dependencies else { return }
        for index in offsets {
            dependencies.blockedBehaviorRepository.delete(blockedBehaviors[index])
        }
        reload()
    }

    /// 「負けそう」ボタンから、特定の「やらないこと」に対するキャラクターの声かけを取得する。
    /// ルーティンセッション外からの呼び出しのため、RoutineEngineには一切触れずCharacterEngineだけを使う。
    func confrontTemptation(_ behavior: BlockedBehavior?) async -> String {
        guard let dependencies else { return "" }
        let response = await dependencies.characterEngine.respond(
            to: .blockedBehaviorDetected(
                behaviorTitle: behavior?.title ?? "",
                counterMessage: behavior?.counterMessage ?? ""
            )
        )
        return response.text
    }
}
