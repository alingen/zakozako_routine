import Foundation

/// キャラクターの口調・煽り強度・返答生成を司るエンジン。
/// 実際の応答文の組み立ては `CharacterResponseGenerating` に委譲するため、
/// ここは「どの状況で、どのプリセットを使って、応答を依頼するか」だけを知っている。
/// 将来 `LocalCharacterResponseGenerator` を `OpenAICharacterResponseGenerator` に
/// 差し替えても、CharacterEngine やその呼び出し元(ConversationCoordinator)は変更不要。
@MainActor
final class CharacterEngine {
    private let generator: CharacterResponseGenerating
    private let characterRepository: CharacterRepository
    private let trustRepository: TrustRepository
    private let userProfileFactRepository: UserProfileFactRepository

    init(
        generator: CharacterResponseGenerating,
        characterRepository: CharacterRepository,
        trustRepository: TrustRepository,
        userProfileFactRepository: UserProfileFactRepository
    ) {
        self.generator = generator
        self.characterRepository = characterRepository
        self.trustRepository = trustRepository
        self.userProfileFactRepository = userProfileFactRepository
    }

    var activePreset: CharacterPreset {
        characterRepository.fetchSelected() ?? .makeDefault()
    }

    func respond(
        to situation: CharacterSituation,
        userText: String? = nil,
        pendingDisclosure: String? = nil,
        history: [ConversationHistoryItem] = []
    ) async -> CharacterResponse {
        let context = CharacterResponseContext(
            situation: situation,
            preset: activePreset,
            recentUserText: userText,
            userNickname: AppSettingsStore.userNickname,
            trustStage: trustRepository.stage,
            userProfileFacts: userProfileFactRepository.allFacts,
            pendingDisclosure: pendingDisclosure,
            history: history
        )
        return await generator.generateResponse(context: context)
    }
}
