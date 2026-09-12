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
            BlockedBehaviorPreset.all.map(\.title),
            [
                "禁煙する",
                "断酒する",
                "鼻をほじらない",
                "ジャンクフードを食べない",
                "コーヒーを飲まない",
                "甘いものをたべない",
                "SNSを見ない",
                "夜ふかしをしない",
                "ゲームをしない",
            ]
        )
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

    func testAllPresetsDefaultToQuitCompletely() {
        for preset in BlockedBehaviorPreset.all {
            XCTAssertEqual(preset.limitRule, .quitCompletely, preset.title)
        }
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

    func testRecordFailureReachesConfiguredLimitImmediately() throws {
        let container = try makeContainer()
        let repository = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(repository.create(title: "コーヒーを飲まない", limitCount: 3))
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))
        )

        let result = try repository.recordFailure(behavior, now: now)

        XCTAssertEqual(result, .recorded)
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: now), 3)
        XCTAssertTrue(behavior.exceededLimit(on: now))
        XCTAssertEqual(behavior.updatedAt, now)
    }

    func testRecordFailureAddsOnlyMissingEventsAndDoesNotDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))
        )
        let behavior = try XCTUnwrap(repository.create(title: "SNSを見ない", limitCount: 3))
        behavior.usageEvents = [now.addingTimeInterval(-60)]
        try context.save()

        XCTAssertEqual(try repository.recordFailure(behavior, now: now), .recorded)
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: now), 3)
        XCTAssertEqual(behavior.usageEvents.count, 3)

        let recordedUpdatedAt = behavior.updatedAt
        XCTAssertEqual(
            try repository.recordFailure(behavior, now: now.addingTimeInterval(60)),
            .alreadyRecorded
        )
        XCTAssertEqual(behavior.usageEvents.count, 3)
        XCTAssertEqual(behavior.updatedAt, recordedUpdatedAt)
    }

    func testRecordFailureRejectsInactiveBehavior() throws {
        let container = try makeContainer()
        let repository = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(repository.create(title: "ゲームをしない"))
        behavior.isActive = false

        XCTAssertThrowsError(try repository.recordFailure(behavior)) { error in
            guard case .inactiveBehavior? = error as? BlockedBehaviorRepositoryError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(behavior.usageEvents.isEmpty)
    }

    func testRecordFailureIsIdempotentUntilFourAMAndRecordsAgainAfterReset() throws {
        let container = try makeContainer()
        let repository = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(repository.create(title: "夜ふかしをしない"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstFailure = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))
        )
        let beforeReset = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 3, minute: 59))
        )
        let afterReset = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 4))
        )

        XCTAssertEqual(
            try repository.recordFailure(behavior, now: firstFailure, calendar: calendar),
            .recorded
        )
        XCTAssertEqual(
            try repository.recordFailure(behavior, now: beforeReset, calendar: calendar),
            .alreadyRecorded
        )
        XCTAssertEqual(
            try repository.recordFailure(behavior, now: afterReset, calendar: calendar),
            .recorded
        )
        XCTAssertEqual(behavior.usageEvents.count, 2)
    }

    func testRecordFailurePersistsForAnotherModelContext() throws {
        let container = try makeContainer()
        let repository = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(repository.create(title: "甘いものをたべない", limitCount: 3))
        let behaviorID = behavior.id
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))
        )

        try repository.recordFailure(behavior, now: now)

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<BlockedBehavior>(
            predicate: #Predicate { $0.id == behaviorID }
        )
        let persisted = try XCTUnwrap(try verificationContext.fetch(descriptor).first)
        XCTAssertEqual(persisted.usageInCurrentPeriod(now: now), 3)
        XCTAssertTrue(persisted.exceededLimit(on: now))
    }

    func testBlockedBehaviorTauntCopyMatchesProductText() {
        XCTAssertEqual(
            BlockedBehaviorTauntKind.struggling.messages,
            [
                "よわよわメンタル出てきたね♡",
                "負けそうだから莉央ちゃんに助け求めにきたんだw",
                "はいはい、見ててあげるから我慢して〜",
            ]
        )
        XCTAssertEqual(
            BlockedBehaviorTauntKind.defeated.messages,
            [
                "ほんとに負けてきたの？w",
                "わざわざ敗北報告しに来たんだ♡",
                "うわ、大人なのに我慢できなかったんだ〜",
            ]
        )
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
