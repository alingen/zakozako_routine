import Foundation
import SwiftData

/// CharacterPreset の永続化・選択状態の管理を担当する。
@MainActor
final class CharacterRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [CharacterPreset] {
        let descriptor = FetchDescriptor<CharacterPreset>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 現在選択中のキャラクター。無ければ先頭のプリセットを返す。
    func fetchSelected() -> CharacterPreset? {
        let all = fetchAll()
        return all.first(where: \.isSelected) ?? all.first
    }

    @discardableResult
    func create(
        name: String,
        description: String,
        basePrompt: String,
        praiseStyle: PraiseStyle,
        scoldStyle: ScoldStyle,
        select: Bool = false
    ) -> CharacterPreset {
        let preset = CharacterPreset(
            name: name,
            presetDescription: description,
            basePrompt: basePrompt,
            praiseStyle: praiseStyle,
            scoldStyle: scoldStyle,
            isSelected: select
        )
        context.insert(preset)
        if select {
            selectExclusively(preset)
        }
        save()
        return preset
    }

    func update(
        _ preset: CharacterPreset,
        praiseStyle: PraiseStyle,
        scoldStyle: ScoldStyle
    ) {
        preset.praiseStyle = praiseStyle
        preset.scoldStyle = scoldStyle
        preset.updatedAt = .now
        save()
    }

    func select(_ preset: CharacterPreset) {
        selectExclusively(preset)
        save()
    }

    private func selectExclusively(_ preset: CharacterPreset) {
        for other in fetchAll() where other.id != preset.id {
            other.isSelected = false
        }
        preset.isSelected = true
    }

    private func save() {
        try? context.save()
    }
}
