import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class CharacterSettingsViewModel {
    private(set) var presets: [CharacterPreset] = []
    private(set) var selectedPreset: CharacterPreset?

    var praiseStyle: PraiseStyle = .teasing
    var scoldStyle: ScoldStyle = .provoking

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
            praiseStyle = selected.praiseStyle
            scoldStyle = selected.scoldStyle
        }
        completionPhrase = AppSettingsStore.completionPhrase
    }

    func saveCompletionPhrase() {
        let trimmed = completionPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettingsStore.completionPhrase = trimmed.isEmpty ? "できた" : trimmed
        reload()
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
            praiseStyle: praiseStyle,
            scoldStyle: scoldStyle
        )
        reload()
    }
}
