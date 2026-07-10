import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class CharacterSettingsViewModel {
    private(set) var presets: [CharacterPreset] = []
    private(set) var selectedPreset: CharacterPreset?

    var name: String = ""
    var description: String = ""
    var praiseStyle: PraiseStyle = .teasing
    var scoldStyle: ScoldStyle = .provoking

    /// OpenAI APIキー。Keychainに保存され、ソースコードやUserDefaultsには一切書き込まれない。
    var openAIAPIKey: String = ""
    private(set) var isUsingOpenAI: Bool = false

    /// 音声/自由入力でこの発言(部分一致)が検出されたら現在のステップを完了として次へ進める。
    var completionPhrase: String = ""

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        presets = dependencies.characterRepository.fetchAll()
        let selected = dependencies.characterRepository.fetchSelected()
        selectedPreset = selected
        if let selected {
            loadFields(from: selected)
        }
        let storedKey = KeychainService.load(key: KeychainService.openAIAPIKeyAccount) ?? ""
        openAIAPIKey = storedKey
        isUsingOpenAI = !storedKey.isEmpty
        completionPhrase = AppSettingsStore.completionPhrase
    }

    func saveCompletionPhrase() {
        let trimmed = completionPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettingsStore.completionPhrase = trimmed.isEmpty ? "できた" : trimmed
        reload()
    }

    private func loadFields(from preset: CharacterPreset) {
        name = preset.name
        description = preset.presetDescription
        praiseStyle = preset.praiseStyle
        scoldStyle = preset.scoldStyle
    }

    func selectPreset(_ preset: CharacterPreset) {
        guard let dependencies else { return }
        dependencies.characterRepository.select(preset)
        reload()
    }

    func save() {
        guard let dependencies, let selectedPreset else { return }
        dependencies.characterRepository.update(
            selectedPreset,
            name: name,
            description: description,
            praiseStyle: praiseStyle,
            scoldStyle: scoldStyle
        )
        reload()
    }

    func saveAPIKey() {
        let trimmed = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainService.delete(key: KeychainService.openAIAPIKeyAccount)
        } else {
            KeychainService.save(key: KeychainService.openAIAPIKeyAccount, value: trimmed)
        }
        reload()
    }

    func clearAPIKey() {
        openAIAPIKey = ""
        KeychainService.delete(key: KeychainService.openAIAPIKeyAccount)
        reload()
    }
}
