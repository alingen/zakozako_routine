import Foundation
import SwiftData
import Observation

/// イベント会話画面の状態管理。小イベント(LINE風UI)用。
///
/// 再生は今日の会話と同じ `ScriptPlayer` を流用する。この ViewModel は
/// 「どのイベントの台本を再生するか」「再生し終えたら完了として記録する」ことを受け持つ。
/// (STEP 6 で大イベント完了時の relationshipPhase 変更をここに追加する)
@Observable
@MainActor
final class EventConversationViewModel {
    private(set) var player: ScriptPlayer?
    private(set) var characterName = "小悪魔コーチ"
    private(set) var eventTitle = ""

    private var dependencies: AppDependencies?
    private var eventId = ""
    private var didHandleFinish = false

    func configure(context: ModelContext, eventId: String) {
        guard dependencies == nil else { return }
        let deps = AppDependencies(context: context)
        dependencies = deps
        self.eventId = eventId
        characterName = deps.characterEngine.activePreset.name

        let script: ConversationScript
        if let definition = deps.eventCatalog.event(id: eventId) {
            eventTitle = definition.title
            script = ConversationScript(messages: definition.messages)
        } else {
            script = ConversationScript(messages: [])
        }
        player = ScriptPlayer(
            script: script,
            factRepository: deps.userProfileFactRepository,
            relationshipPhase: deps.relationshipRepository.phase
        ) { [weak self] in
            self?.handleFinished()
        }
    }

    func start() async {
        await player?.start()
    }

    func selectChoice(_ choice: ScriptChoice) async {
        await player?.selectChoice(choice)
    }

    private func handleFinished() {
        guard !didHandleFinish, let dependencies else { return }
        didHandleFinish = true
        dependencies.eventProgressRepository.markCompleted(eventId: eventId)
    }
}
