import Foundation
import SwiftData
import Observation

/// 大イベント画面の状態管理。ギャルゲー風の専用UI(BigEventView)用。
///
/// 再生ロジックは共通の `ScriptPlayer` を `autoAdvance: false` で使う(タップで1メッセージずつ送り)。
/// この ViewModel は台本の読み込みと、完了時の副作用(イベント完了記録、関係性フェーズの前進)を受け持つ。
@Observable
@MainActor
final class BigEventViewModel {
    private(set) var player: ScriptPlayer?
    private(set) var characterName = "小悪魔コーチ"
    private(set) var eventTitle = ""
    /// イベント既定の背景画像名。各メッセージの `background` が指定されていればそちらを優先。
    private(set) var defaultBackground: String?

    private var dependencies: AppDependencies?
    private var eventId = ""
    private var advancesToPhase: Int?
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
            defaultBackground = definition.background
            advancesToPhase = definition.advancesToPhase
            script = ConversationScript(messages: definition.messages)
        } else {
            script = ConversationScript(messages: [])
        }
        player = ScriptPlayer(
            script: script,
            factRepository: deps.userProfileFactRepository,
            autoAdvance: false,
            relationshipPhase: deps.relationshipRepository.phase
        ) { [weak self] in
            self?.handleFinished()
        }
    }

    func start() async {
        await player?.start()
    }

    /// テキストウィンドウのタップで次のメッセージへ。
    func advance() async {
        await player?.advance()
    }

    func selectChoice(_ choice: ScriptChoice) async {
        await player?.selectChoice(choice)
    }

    /// 名前ウィンドウに出す話者名。メッセージ側の指定 > キャラクター名(キャラ発言時) > なし。
    func speakerName(for message: ScriptMessage?) -> String? {
        guard let message else { return nil }
        if let explicit = message.speakerName, !explicit.isEmpty { return explicit }
        return message.speaker == .character ? characterName : nil
    }

    private func handleFinished() {
        guard !didHandleFinish, let dependencies else { return }
        didHandleFinish = true
        dependencies.eventProgressRepository.markCompleted(eventId: eventId)
        if let phase = advancesToPhase {
            dependencies.relationshipRepository.advance(toPhase: phase)
        }
    }
}
