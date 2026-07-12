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
