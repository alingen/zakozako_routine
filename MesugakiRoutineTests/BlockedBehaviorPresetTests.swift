import SwiftData
import UIKit
import XCTest
@testable import MesugakiRoutine

@MainActor
final class BlockedBehaviorPresetTests: XCTestCase {
    private var container: ModelContainer?

    func testCatalogUsesUniqueIdentifiersAndAvailableIcons() {
        XCTAssertFalse(BlockedBehaviorPreset.all.isEmpty)
        XCTAssertEqual(
            Set(BlockedBehaviorPreset.all.map(\.id)).count,
            BlockedBehaviorPreset.all.count
        )
        XCTAssertEqual(
            Set(BlockedBehaviorPreset.all.map(\.title)).count,
            BlockedBehaviorPreset.all.count
        )

        for preset in BlockedBehaviorPreset.all {
            XCTAssertFalse(preset.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(BlockedBehaviorIcon.all.contains(preset.iconName), preset.iconName)
            XCTAssertNotNil(UIImage(systemName: preset.iconName), preset.iconName)
            XCTAssertGreaterThanOrEqual(preset.limitRule.failureCount, 1)
        }
    }

    func testApplyingQuitCompletelyPresetFillsDraft() throws {
        let preset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "quit-smoking" }
        )
        var draft = BlockedBehaviorDraft()

        draft.apply(preset)

        XCTAssertEqual(draft.title, preset.title)
        XCTAssertEqual(draft.iconName, preset.iconName)
        XCTAssertTrue(draft.isQuitCompletely)
        XCTAssertEqual(draft.effectiveLimitPeriod, .day)
        XCTAssertEqual(draft.effectiveLimitCount, 1)
    }

    func testApplyingCountedPresetFillsItsLimitRule() throws {
        let preset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "reduce-alcohol" }
        )
        var draft = BlockedBehaviorDraft()

        draft.apply(preset)

        XCTAssertFalse(draft.isQuitCompletely)
        XCTAssertEqual(draft.limitPeriod, .week)
        XCTAssertEqual(draft.limitCount, 4)
        XCTAssertEqual(draft.effectiveLimitPeriod, .week)
        XCTAssertEqual(draft.effectiveLimitCount, 4)
    }

    func testCustomResetClearsPreviouslySelectedPreset() {
        var draft = BlockedBehaviorDraft()
        draft.apply(BlockedBehaviorPreset.all[0])
        draft.reset()

        XCTAssertEqual(draft.title, "")
        XCTAssertNil(draft.iconName)
        XCTAssertTrue(draft.isQuitCompletely)
        XCTAssertEqual(draft.limitPeriod, .day)
        XCTAssertEqual(draft.limitCount, 1)
        XCTAssertFalse(draft.canSave)
    }

    func testPresetIsNotPersistedUntilSaveAndOnlyOneCanBeActive() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        var draft = BlockedBehaviorDraft()
        draft.apply(BlockedBehaviorPreset.all[0])

        XCTAssertTrue(try context.fetch(FetchDescriptor<BlockedBehavior>()).isEmpty)

        let saved = try XCTUnwrap(repository.create(
            title: draft.title,
            iconName: draft.iconName,
            limitPeriod: draft.effectiveLimitPeriod,
            limitCount: draft.effectiveLimitCount
        ))
        XCTAssertEqual(saved.title, draft.title)
        XCTAssertEqual(saved.iconName, draft.iconName)
        XCTAssertEqual(saved.limitPeriod, .day)
        XCTAssertEqual(saved.limitCount, 1)

        XCTAssertNil(repository.create(title: "2件目"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<BlockedBehavior>()).count, 1)

        XCTAssertTrue(repository.delete(saved))
        XCTAssertTrue(repository.canAddNew())
    }

    func testSeederLeavesBlockedBehaviorEmptySoPresetFlowIsReachable() throws {
        let container = try makeContainer()
        let context = container.mainContext

        DataSeeder.seedIfNeeded(context: context)
        DataSeeder.seedIfNeeded(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<BlockedBehavior>()).isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Routine.self,
            BlockedBehavior.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        return container
    }
}
