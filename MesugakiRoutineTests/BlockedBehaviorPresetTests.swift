import SwiftData
import FamilyControls
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
                "スマホを見ない",
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

    func testOnboardingCatalogUsesRequestedPresetsAndScreenTimeOnlyForVideo() {
        XCTAssertEqual(
            BlockedBehaviorPreset.onboarding.map(\.title),
            [
                "動画をだらだら見る",
                "SNSを見る",
                "タバコを吸う",
                "お酒を飲む",
                "間食をする",
            ]
        )
        XCTAssertEqual(
            Set(BlockedBehaviorPreset.onboarding.map(\.id)).count,
            BlockedBehaviorPreset.onboarding.count
        )
        let videoPreset = BlockedBehaviorPreset.onboarding.first
        XCTAssertEqual(videoPreset?.id, OnboardingBlockedBehaviorDraft.screenTimeVideoID)
        XCTAssertEqual(videoPreset?.trackingKind, .screenTime)
        XCTAssertEqual(videoPreset?.screenTimeLimitMinutes, 20)

        let remainingPresets = BlockedBehaviorPreset.onboarding.dropFirst()
        XCTAssertTrue(remainingPresets.allSatisfy { $0.trackingKind == .manual })
        XCTAssertTrue(
            BlockedBehaviorPreset.onboarding.allSatisfy { $0.limitRule == .quitCompletely }
        )

        for preset in BlockedBehaviorPreset.onboarding {
            XCTAssertTrue(BlockedBehaviorIcon.all.contains(preset.iconName), preset.iconName)
            XCTAssertNotNil(UIImage(systemName: preset.iconName), preset.iconName)
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

    func testOnlySmartphonePresetUsesScreenTimeTracking() {
        XCTAssertEqual(
            BlockedBehaviorPreset.all.filter { $0.trackingKind == .screenTime }.map(\.id),
            ["no-smartphone"]
        )
        XCTAssertTrue(
            BlockedBehaviorPreset.all
                .filter { $0.id != "no-smartphone" }
                .allSatisfy { $0.trackingKind == .manual }
        )
    }

    func testScreenTimePresetDefaultsToTwentyMinutesAndRequiresSelection() throws {
        let preset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "no-smartphone" }
        )
        var draft = BlockedBehaviorDraft()

        XCTAssertEqual(BlockedBehaviorPreset.all.first?.id, preset.id)
        XCTAssertEqual(preset.trackingKind, .screenTime)
        XCTAssertEqual(preset.screenTimeLimitMinutes, 20)

        draft.apply(preset)

        XCTAssertEqual(draft.trackingKind, .screenTime)
        XCTAssertEqual(draft.screenTimeLimitMinutes, 20)
        XCTAssertFalse(draft.canSave)
        XCTAssertNotNil(draft.screenTimeSelectionData)
    }

    func testScreenTimeMonitorUsesConfiguredLimitAndFourAMBoundary() {
        let threshold = ScreenTimeMonitoringService.thresholdComponents(limitMinutes: 20)
        let schedule = ScreenTimeMonitoringService.dailySchedule

        XCTAssertEqual(threshold.minute, 20)
        XCTAssertEqual(threshold.hour, 0)
        XCTAssertEqual(
            ScreenTimeMonitoringService.thresholdComponents(limitMinutes: 90).hour,
            1
        )
        XCTAssertEqual(
            ScreenTimeMonitoringService.thresholdComponents(limitMinutes: 90).minute,
            30
        )
        XCTAssertEqual(schedule.intervalStart.hour, AppDay.startHour)
        XCTAssertEqual(schedule.intervalStart.minute, 0)
        XCTAssertEqual(schedule.intervalEnd.hour, AppDay.startHour - 1)
        XCTAssertEqual(schedule.intervalEnd.minute, 59)
        XCTAssertTrue(schedule.repeats)
        XCTAssertNotNil(schedule.nextInterval)
    }

    func testScreenTimeAuthorizationConflictUsesActionableJapaneseMessage() {
        let error = ScreenTimeMonitoringError.fromAuthorizationError(
            FamilyControlsError.authorizationConflict
        )

        guard case .authorizationConflict = error else {
            return XCTFail("Expected authorizationConflict, got \(error)")
        }
        XCTAssertTrue(error.offersSettingsAction)
        XCTAssertTrue(error.localizedDescription.contains("ほかのスクリーンタイム管理アプリ"))
        XCTAssertTrue(error.localizedDescription.contains("設定"))
    }

    func testCanceledScreenTimeAuthorizationDoesNotOfferSettings() {
        let error = ScreenTimeMonitoringError.fromAuthorizationError(
            FamilyControlsError.authorizationCanceled
        )

        guard case .authorizationCanceled = error else {
            return XCTFail("Expected authorizationCanceled, got \(error)")
        }
        XCTAssertFalse(error.offersSettingsAction)
    }

    func testApprovedScreenTimeAuthorizationSkipsSystemRequest() async throws {
        var requestCount = 0
        let coordinator = ScreenTimeAuthorizationCoordinator(
            statusProvider: { .approved },
            requestOperation: { requestCount += 1 }
        )

        try await coordinator.requestAuthorizationIfNeeded()

        XCTAssertEqual(requestCount, 0)
    }

    func testConcurrentScreenTimeAuthorizationSharesOneSystemRequest() async throws {
        var status = AuthorizationStatus.notDetermined
        var requestCount = 0
        let coordinator = ScreenTimeAuthorizationCoordinator(
            statusProvider: { status },
            requestOperation: {
                requestCount += 1
                try await Task.sleep(for: .milliseconds(50))
                status = .approved
            }
        )

        let first = Task { @MainActor in
            try await coordinator.requestAuthorizationIfNeeded()
        }
        await Task.yield()
        let second = Task { @MainActor in
            try await coordinator.requestAuthorizationIfNeeded()
        }

        try await first.value
        try await second.value

        XCTAssertEqual(requestCount, 1)
    }

    func testScreenTimeMonitorEventNameKeepsBehaviorIdentity() {
        let behaviorID = UUID()
        let rawName = ScreenTimeMonitorShared.eventRawName(
            for: behaviorID,
            limitMinutes: 20
        )
        let activityRawName = ScreenTimeMonitorShared.activityRawName(for: behaviorID)

        XCTAssertEqual(
            ScreenTimeMonitorShared.behaviorID(fromEventRawName: rawName),
            behaviorID
        )
        XCTAssertEqual(
            ScreenTimeMonitorShared.limitMinutes(fromEventRawName: rawName),
            20
        )
        XCTAssertEqual(
            ScreenTimeMonitorShared.behaviorID(fromActivityRawName: activityRawName),
            behaviorID
        )
        XCTAssertNil(ScreenTimeMonitorShared.behaviorID(fromEventRawName: "other-event"))
        XCTAssertNil(ScreenTimeMonitorShared.behaviorID(fromActivityRawName: "other-activity"))
    }

    func testEmptyScreenTimeSelectionCanRoundTripThroughStoredData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let selection = FamilyActivitySelection()
        let selectionData = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            trackingKind: .screenTime,
            screenTimeLimitMinutes: 20,
            screenTimeSelectionData: selectionData
        )
        let behaviorID = behavior.id

        context.insert(behavior)
        try context.save()

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<BlockedBehavior>(
            predicate: #Predicate { $0.id == behaviorID }
        )
        let persisted = try XCTUnwrap(try verificationContext.fetch(descriptor).first)

        XCTAssertEqual(decoded, selection)
        XCTAssertEqual(persisted.trackingKind, .screenTime)
        XCTAssertEqual(persisted.screenTimeLimitMinutes, 20)
        XCTAssertEqual(persisted.screenTimeSelectionData, selectionData)
    }

    func testBlockedBehaviorUsesManualCompatibleDefaultsAndClampsScreenTimeLimit() {
        let behavior = BlockedBehavior(title: "禁煙する")

        behavior.trackingKindRawValue = nil
        behavior.screenTimeLimitMinutesValue = nil
        XCTAssertEqual(behavior.trackingKind, .manual)
        XCTAssertEqual(behavior.screenTimeLimitMinutes, 20)

        behavior.screenTimeLimitMinutes = 0
        XCTAssertEqual(behavior.screenTimeLimitMinutes, 1)
        behavior.screenTimeLimitMinutes = 2_000
        XCTAssertEqual(behavior.screenTimeLimitMinutes, 1_440)
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
        XCTAssertEqual(draft.trackingKind, .manual)
        XCTAssertEqual(draft.screenTimeLimitMinutes, 20)
        XCTAssertEqual(draft.screenTimeSelection, FamilyActivitySelection())
        XCTAssertFalse(draft.canSave)
    }

    func testApplyingManualPresetClearsScreenTimeConfiguration() throws {
        let screenTimePreset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "no-smartphone" }
        )
        let manualPreset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "quit-smoking" }
        )
        var draft = BlockedBehaviorDraft()

        draft.apply(screenTimePreset)
        draft.screenTimeLimitMinutes = 90
        draft.apply(manualPreset)

        XCTAssertEqual(draft.trackingKind, .manual)
        XCTAssertEqual(draft.screenTimeLimitMinutes, 20)
        XCTAssertEqual(draft.screenTimeSelection, FamilyActivitySelection())
        XCTAssertTrue(draft.canSave)
    }

    func testPresetIsNotPersistedUntilSaveAndOnlyOneCanBeActive() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        var draft = BlockedBehaviorDraft()
        let preset = try XCTUnwrap(
            BlockedBehaviorPreset.all.first { $0.id == "quit-smoking" }
        )
        draft.apply(preset)

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

    func testDraftLoadsExistingBehaviorForEditing() {
        let behavior = BlockedBehavior(
            title: "SNSを見ない",
            iconName: "bubble.left.and.bubble.right",
            limitPeriod: .week,
            limitCount: 3,
            currentStreakDays: 5
        )

        let draft = BlockedBehaviorDraft(behavior: behavior)

        XCTAssertEqual(draft.title, "SNSを見ない")
        XCTAssertEqual(draft.iconName, "bubble.left.and.bubble.right")
        XCTAssertFalse(draft.isQuitCompletely)
        XCTAssertEqual(draft.limitPeriod, .week)
        XCTAssertEqual(draft.limitCount, 3)
        XCTAssertEqual(draft.trackingKind, .manual)
        XCTAssertTrue(draft.canSave)
    }

    func testUpdatingBehaviorPersistsSettingsWithoutChangingProgress() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        let eventDate = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = eventDate.addingTimeInterval(600)
        let behavior = try XCTUnwrap(repository.create(title: "ゲームをしない"))
        behavior.usageEvents = [eventDate]
        behavior.currentStreakDays = 4
        try context.save()
        let behaviorID = behavior.id

        XCTAssertTrue(repository.update(
            behavior,
            title: "夜にゲームをしない",
            iconName: "gamecontroller.fill",
            limitPeriod: .week,
            limitCount: 3,
            trackingKind: .manual,
            screenTimeLimitMinutes: nil,
            screenTimeSelectionData: nil,
            now: updatedAt
        ))

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<BlockedBehavior>(
            predicate: #Predicate { $0.id == behaviorID }
        )
        let persisted = try XCTUnwrap(try verificationContext.fetch(descriptor).first)
        XCTAssertEqual(persisted.title, "夜にゲームをしない")
        XCTAssertEqual(persisted.iconName, "gamecontroller.fill")
        XCTAssertEqual(persisted.limitPeriod, .week)
        XCTAssertEqual(persisted.limitCount, 3)
        XCTAssertEqual(persisted.usageEvents, [eventDate])
        XCTAssertEqual(persisted.currentStreakDays, 4)
        XCTAssertEqual(persisted.updatedAt, updatedAt)
    }

    func testSeederLeavesBlockedBehaviorEmptySoPresetFlowIsReachable() throws {
        let container = try makeContainer()
        let context = container.mainContext

        DataSeeder.seedIfNeeded(context: context)
        DataSeeder.seedIfNeeded(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<BlockedBehavior>()).isEmpty)
    }

    func testRecordFailureConsumesOneCountAndFailsOnlyAtConfiguredLimit() throws {
        let container = try makeContainer()
        let repository = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(repository.create(title: "コーヒーを飲まない", limitCount: 10))
        let now = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))
        )

        XCTAssertEqual(try repository.recordFailure(behavior, now: now), .recorded)
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: now), 1)
        XCTAssertFalse(behavior.exceededLimit(on: now))

        for offset in 1..<9 {
            XCTAssertEqual(
                try repository.recordFailure(
                    behavior,
                    now: now.addingTimeInterval(TimeInterval(offset))
                ),
                .recorded
            )
        }
        let ninthFailureTime = now.addingTimeInterval(8)
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: ninthFailureTime), 9)
        XCTAssertFalse(behavior.exceededLimit(on: ninthFailureTime))

        let tenthFailureTime = now.addingTimeInterval(9)
        XCTAssertEqual(
            try repository.recordFailure(behavior, now: tenthFailureTime),
            .recorded
        )

        XCTAssertEqual(behavior.usageInCurrentPeriod(now: tenthFailureTime), 10)
        XCTAssertTrue(behavior.exceededLimit(on: tenthFailureTime))
        XCTAssertEqual(behavior.updatedAt, tenthFailureTime)

        XCTAssertEqual(
            try repository.recordFailure(
                behavior,
                now: tenthFailureTime.addingTimeInterval(1)
            ),
            .alreadyRecorded
        )
        XCTAssertEqual(behavior.usageEvents.count, 10)
    }

    func testRecordFailureAddsOneEventAndStopsAtLimit() throws {
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
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: now), 2)
        XCTAssertEqual(behavior.usageEvents.count, 2)

        let limitTime = now.addingTimeInterval(60)
        XCTAssertEqual(try repository.recordFailure(behavior, now: limitTime), .recorded)
        XCTAssertEqual(behavior.usageInCurrentPeriod(now: limitTime), 3)
        XCTAssertEqual(behavior.usageEvents.count, 3)

        let recordedUpdatedAt = behavior.updatedAt
        XCTAssertEqual(
            try repository.recordFailure(behavior, now: now.addingTimeInterval(120)),
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
        XCTAssertEqual(persisted.usageInCurrentPeriod(now: now), 1)
        XCTAssertFalse(persisted.exceededLimit(on: now))
    }

    func testScreenTimeProgressUsesOnlyVerifiedDaysAndLateFailureRecalculatesStreak() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 4))
        )
        let thirdDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            trackingKind: .screenTime,
            createdAt: firstDay
        )
        context.insert(behavior)
        try context.save()

        XCTAssertTrue(try repository.recordScreenTimeSignal(
            ScreenTimeMonitorSignal(
                behaviorID: behavior.id,
                appDayStart: firstDay,
                occurredAt: firstDay.addingTimeInterval(86_399),
                kind: .intervalCompleted
            ),
            for: behavior,
            calendar: calendar
        ))
        XCTAssertTrue(try repository.recordScreenTimeSignal(
            ScreenTimeMonitorSignal(
                behaviorID: behavior.id,
                appDayStart: thirdDay,
                occurredAt: thirdDay.addingTimeInterval(86_399),
                kind: .intervalCompleted
            ),
            for: behavior,
            calendar: calendar
        ))

        // 2日目は監視完了通知がないため、成功にも失敗にもせず加算しない。
        XCTAssertEqual(behavior.currentStreakDays, 2)
        XCTAssertEqual(behavior.screenTimeVerifiedDays.count, 2)

        let delayedFailure = ScreenTimeMonitorSignal(
            behaviorID: behavior.id,
            appDayStart: firstDay,
            occurredAt: thirdDay.addingTimeInterval(120),
            kind: .thresholdExceeded
        )
        XCTAssertTrue(try repository.recordScreenTimeSignal(
            delayedFailure,
            for: behavior,
            calendar: calendar
        ))

        // 1日目は監視完了済みでも失敗が優先され、その後の成功1日だけが残る。
        XCTAssertEqual(behavior.currentStreakDays, 1)
        XCTAssertTrue(behavior.exceededLimit(on: firstDay, calendar: calendar))
        XCTAssertEqual(behavior.lastCheckInDate, thirdDay)
        XCTAssertFalse(try repository.recordScreenTimeSignal(
            delayedFailure,
            for: behavior,
            calendar: calendar
        ))
    }

    func testLateScreenTimeFailureReversesPrematureMastery() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 4))
        )
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            trackingKind: .screenTime,
            createdAt: firstDay
        )
        context.insert(behavior)
        try context.save()

        for offset in 0..<BlockedBehavior.masteryStreakDays {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
            _ = try repository.recordScreenTimeSignal(
                ScreenTimeMonitorSignal(
                    behaviorID: behavior.id,
                    appDayStart: day,
                    occurredAt: day.addingTimeInterval(86_399),
                    kind: .intervalCompleted
                ),
                for: behavior,
                calendar: calendar
            )
        }

        XCTAssertNotNil(behavior.masteredAt)
        XCTAssertFalse(behavior.isActive)
        XCTAssertEqual(behavior.currentStreakDays, BlockedBehavior.masteryStreakDays)

        XCTAssertTrue(try repository.recordScreenTimeSignal(
            ScreenTimeMonitorSignal(
                behaviorID: behavior.id,
                appDayStart: firstDay,
                occurredAt: firstDay.addingTimeInterval(60),
                kind: .thresholdExceeded
            ),
            for: behavior,
            calendar: calendar
        ))

        XCTAssertNil(behavior.masteredAt)
        XCTAssertTrue(behavior.isActive)
        XCTAssertEqual(behavior.currentStreakDays, BlockedBehavior.masteryStreakDays - 1)
    }

    func testAutoEvaluateNeverTreatsMissingScreenTimeSignalAsSuccess() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        let now = Date()
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            trackingKind: .screenTime,
            createdAt: now.addingTimeInterval(-3 * 86_400)
        )
        context.insert(behavior)
        try context.save()

        XCTAssertEqual(repository.autoEvaluate(behavior, now: now), 0)
        XCTAssertEqual(behavior.currentStreakDays, 0)
        XCTAssertNil(behavior.lastCheckInDate)
    }

    func testScreenTimeCompletionCannotMarkCurrentDayAsSuccess() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = BlockedBehaviorRepository(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))
        )
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            trackingKind: .screenTime,
            createdAt: now.addingTimeInterval(-86_400)
        )
        context.insert(behavior)
        try context.save()
        let signal = ScreenTimeMonitorSignal(
            behaviorID: behavior.id,
            appDayStart: AppDay.startOfDay(for: now, calendar: calendar),
            occurredAt: now,
            kind: .intervalCompleted
        )

        XCTAssertThrowsError(try repository.recordScreenTimeSignal(
            signal,
            for: behavior,
            processedAt: now,
            calendar: calendar
        )) { error in
            guard case .screenTimeSignalNotReady? = error as? BlockedBehaviorRepositoryError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(behavior.currentStreakDays, 0)
        XCTAssertTrue(behavior.screenTimeVerifiedDays.isEmpty)
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
            UserActionEvent.self,
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
