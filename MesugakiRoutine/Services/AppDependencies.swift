import Foundation
import SwiftData

/// ModelContext から Repository / Engine / Coordinator を組み立てるための簡易ファクトリ。
/// ViewModel はこれを通じて依存を取得することで、SwiftUI の View から直接 SwiftData を触らない。
@MainActor
struct AppDependencies {
    let routineRepository: RoutineRepository
    let characterRepository: CharacterRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let sessionRepository: RoutineSessionRepository
    let routineEngine: RoutineEngine
    let characterEngine: CharacterEngine
    let conversationCoordinator: ConversationCoordinator

    init(context: ModelContext) {
        routineRepository = RoutineRepository(context: context)
        characterRepository = CharacterRepository(context: context)
        blockedBehaviorRepository = BlockedBehaviorRepository(context: context)
        sessionRepository = RoutineSessionRepository(context: context)
        routineEngine = RoutineEngine(sessionRepository: sessionRepository)
        // Keychain に OpenAI APIキーが保存されていれば ChatGPT(Chat Completions API) で応答を生成し、
        // なければローカルテンプレートにフォールバックする。キーの有無だけで自動的に切り替わる。
        let generator: CharacterResponseGenerating
        if let apiKey = KeychainService.load(key: KeychainService.openAIAPIKeyAccount), !apiKey.isEmpty {
            generator = OpenAICharacterResponseGenerator(
                apiKeyProvider: { KeychainService.load(key: KeychainService.openAIAPIKeyAccount) }
            )
        } else {
            generator = LocalCharacterResponseGenerator()
        }
        characterEngine = CharacterEngine(
            generator: generator,
            characterRepository: characterRepository
        )
        conversationCoordinator = ConversationCoordinator(
            routineEngine: routineEngine,
            characterEngine: characterEngine,
            blockedBehaviorRepository: blockedBehaviorRepository
        )
    }
}
