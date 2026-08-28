import Foundation
import SwiftData
import Observation

/// 「今日の会話」画面の状態管理。
///
/// 会話の再生そのものは共通の `ScriptPlayer` に委譲する。この ViewModel は
/// 「どの台本を再生するか」「再生し終えた後に何をするか(会話インデックスの前進、イベント解放の再評価、
/// 解放済みイベントの予告表示)」だけを受け持つ。信頼度には一切触れない(今日の会話は信頼度と非連動)。
@Observable
@MainActor
final class TodayConversationViewModel {
    private(set) var player: ScriptPlayer?
    private(set) var characterName = "小悪魔コーチ"
    /// 表示用の「Day N」。
    private(set) var dayNumber = 1
    /// 今日の会話を完了した後に見つかった、解放済み(未完了)のイベント。あれば予告を出す。
    private(set) var pendingEvent: EventDefinition?

    private var dependencies: AppDependencies?
    private var didHandleFinish = false

    func configure(context: ModelContext) {
        guard dependencies == nil else { return }
        let deps = AppDependencies(context: context)
        dependencies = deps
        characterName = deps.characterEngine.activePreset.name

        let index = deps.dailyConversationStateRepository.currentIndex
        dayNumber = index + 1
        let script = deps.dailyConversationProvider.script(forIndex: index) ?? ConversationScript(messages: [])
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

    /// 「あとにする」を押した時。イベントは解放済みのまま残す(次回また予告される)。
    func deferPendingEvent() {
        guard let dependencies, let event = pendingEvent else { return }
        dependencies.eventProgressRepository.markDeferred(eventId: event.eventId)
    }

    private func handleFinished() {
        guard !didHandleFinish, let dependencies else { return }
        didHandleFinish = true
        dependencies.dailyConversationStateRepository.advance()
        dependencies.eventUnlockService.refreshUnlocks()
        pendingEvent = dependencies.eventUnlockService.nextPresentableEvent()
    }
}
