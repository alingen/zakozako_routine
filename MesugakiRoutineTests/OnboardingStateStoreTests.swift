import XCTest
@testable import MesugakiRoutine

@MainActor
final class OnboardingStateStoreTests: XCTestCase {
    func testNewStoreStartsAtFirstDedicatedScreen() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertEqual(store.setupStep, .introduction)
            XCTAssertEqual(store.phase, .dedicatedSetup)
            XCTAssertEqual(store.draft, OnboardingDraft())
            XCTAssertNil(store.createdRoutineID)
            XCTAssertFalse(store.isCompleted)
            XCTAssertTrue(store.shouldPresentDedicatedSetup)
            XCTAssertFalse(store.isRunningInAppTutorial)
        }
    }

    func testDraftAndSetupStepResumeAfterRecreatingStore() {
        withDefaults { defaults in
            let first = OnboardingStateStore(defaults: defaults)
            first.draft.userName = "かずし"
            first.draft.userHonorific = .ojisan
            first.draft.selectedHabitID = "onboarding-read"
            first.draft.habitTitle = "本を読む"
            first.draft.habitIconName = "book"

            XCTAssertTrue(first.advanceSetup())
            XCTAssertEqual(first.setupStep, .habitSelection)
            XCTAssertTrue(first.advanceSetup())

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .goalSetting)
            XCTAssertEqual(restored.draft.userName, "かずし")
            XCTAssertEqual(restored.draft.userHonorific, .ojisan)
            XCTAssertEqual(restored.draft.selectedHabitID, "onboarding-read")
            XCTAssertEqual(restored.draft.habitTitle, "本を読む")
            XCTAssertEqual(restored.draft.habitIconName, "book")
        }
    }

    func testSetupCannotAdvanceUntilCurrentInputIsValid() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertFalse(store.advanceSetup())
            store.draft.userName = "  "
            XCTAssertFalse(store.advanceSetup())

            store.draft.userName = "かずし"
            XCTAssertTrue(store.advanceSetup())

            store.draft.habitTitle = "本を読む"
            XCTAssertFalse(store.advanceSetup(), "選択IDのないタイトルだけでは進めない")
            store.draft.selectedHabitID = "onboarding-read"
            XCTAssertTrue(store.advanceSetup())

            store.draft.selectedGoalID = "one-page"
            store.draft.routineTitle = "本を1ページ読む"
            XCTAssertTrue(store.advanceSetup())

            store.draft.selectedCueID = "before-bed"
            store.draft.cueText = "寝る前"
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .confirmation)
            XCTAssertFalse(store.advanceSetup(), "最終確認後はRoutine保存APIを明示的に呼ぶ")
        }
    }

    func testFullInAppFlowPersistsRoutineAndUserChoices() {
        withDefaults { defaults in
            let routineID = UUID()
            let first = OnboardingStateStore(defaults: defaults)
            first.draft.userName = "かずし"
            first.draft.selectedHabitID = "onboarding-read"
            first.draft.habitTitle = "本を読む"
            first.draft.selectedGoalID = "one-page"
            first.draft.goalText = "1ページ"
            first.draft.routineTitle = "本を1ページ読む"
            first.draft.selectedCueID = "before-bed"
            first.draft.cueText = "寝る前"

            first.beginInAppTutorial(createdRoutineID: routineID)
            first.completeFirstReport(with: .deferred)
            first.completeConversationPrompt(with: .later)

            let beforeStoryPresentation = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(beforeStoryPresentation.createdRoutineID, routineID)
            XCTAssertEqual(beforeStoryPresentation.firstReportOutcome, .deferred)
            XCTAssertEqual(beforeStoryPresentation.conversationChoice, .later)
            XCTAssertEqual(beforeStoryPresentation.phase, .storyUnlockPresentation)
            XCTAssertTrue(beforeStoryPresentation.isRunningInAppTutorial)

            beforeStoryPresentation.completeStoryUnlockPresentation()
            beforeStoryPresentation.completeOnboarding(
                notificationChoice: .enabled,
                reminderMinuteOfDay: 23 * 60 + 30
            )

            let completed = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(completed.phase, .completed)
            XCTAssertTrue(completed.isCompleted)
            XCTAssertFalse(completed.shouldPresentDedicatedSetup)
            XCTAssertFalse(completed.isRunningInAppTutorial)
            XCTAssertEqual(completed.createdRoutineID, routineID)
            XCTAssertEqual(completed.notificationChoice, .enabled)
            XCTAssertEqual(completed.draft.reminderMinuteOfDay, 23 * 60 + 30)
        }
    }

    func testOutOfOrderPhaseMutationsAreIgnored() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            store.completeFirstReport(with: .completed)
            store.completeConversationPrompt(with: .started)
            store.completeStoryUnlockPresentation()
            store.completeOnboarding(notificationChoice: .notNow)

            XCTAssertEqual(store.phase, .dedicatedSetup)
            XCTAssertNil(store.firstReportOutcome)
            XCTAssertNil(store.conversationChoice)
            XCTAssertNil(store.notificationChoice)
            XCTAssertFalse(store.isCompleted)
        }
    }

    func testResetClearsPersistedProgressAndDraft() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            store.beginInAppTutorial(createdRoutineID: UUID())
            store.completeFirstReport(with: .completed)

            store.reset()

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .introduction)
            XCTAssertEqual(restored.phase, .dedicatedSetup)
            XCTAssertEqual(restored.draft, OnboardingDraft())
            XCTAssertNil(restored.createdRoutineID)
            XCTAssertNil(restored.firstReportOutcome)
            XCTAssertFalse(restored.isCompleted)
        }
    }

    func testUnreadableStoredValueFallsBackToInitialState() {
        withDefaults { defaults in
            defaults.set(Data("not-json".utf8), forKey: OnboardingStateStore.defaultStorageKey)

            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertEqual(store.setupStep, .introduction)
            XCTAssertEqual(store.phase, .dedicatedSetup)
            XCTAssertEqual(store.draft, OnboardingDraft())
            XCTAssertFalse(store.isCompleted)
        }
    }

    func testReminderMinuteIsClampedToOneDay() {
        var draft = OnboardingDraft(reminderMinuteOfDay: -1)
        XCTAssertEqual(draft.reminderMinuteOfDay, 0)

        draft.setReminderMinuteOfDay(1_440)
        XCTAssertEqual(draft.reminderMinuteOfDay, 1_439)

        draft.setReminderMinuteOfDay(nil)
        XCTAssertNil(draft.reminderMinuteOfDay)
    }

    func testConversationIdentityPersistsPastOnboardingUntilExplicitlyCleared() {
        withDefaults { defaults in
            let identity = OnboardingConversationIdentity(
                scenarioID: "daily_special",
                playbackKey: "daily:2026-09-20"
            )
            let first = OnboardingStateStore(defaults: defaults)
            first.recordConversationIdentity(identity)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.conversationIdentity, identity)

            restored.clearConversationIdentity()
            XCTAssertNil(OnboardingStateStore(defaults: defaults).conversationIdentity)
        }
    }

    func testExistingInstallationWithoutOnboardingStateIsMigratedAsCompleted() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertTrue(store.startedWithoutSavedState)
            store.completeForExistingInstallationIfNeeded(hasExistingUserData: true)

            XCTAssertTrue(store.isCompleted)
            XCTAssertEqual(store.phase, .completed)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertFalse(restored.startedWithoutSavedState)
            XCTAssertTrue(restored.isCompleted)
        }
    }

    func testFreshInstallationWithoutUserDataStillShowsOnboarding() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            store.completeForExistingInstallationIfNeeded(hasExistingUserData: false)

            XCTAssertFalse(store.isCompleted)
            XCTAssertEqual(store.phase, .dedicatedSetup)
        }
    }

    func testCompletedRoutineRepairsInterruptedFirstReportTransition() {
        withDefaults { defaults in
            let routineID = UUID()
            let store = OnboardingStateStore(defaults: defaults)
            store.beginInAppTutorial(createdRoutineID: routineID)

            store.reconcileFirstReportIfNeeded(isRoutineComplete: true)

            XCTAssertEqual(store.firstReportOutcome, .completed)
            XCTAssertEqual(store.phase, .conversationPrompt)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.firstReportOutcome, .completed)
            XCTAssertEqual(restored.phase, .conversationPrompt)
        }
    }

    func testIncompleteRoutineDoesNotAdvanceFirstReport() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.beginInAppTutorial(createdRoutineID: UUID())

            store.reconcileFirstReportIfNeeded(isRoutineComplete: false)

            XCTAssertNil(store.firstReportOutcome)
            XCTAssertEqual(store.phase, .firstReport)
        }
    }

    func testNotificationSetupPersistsRollbackValuesAndFirstFireLowerBound() throws {
        try withDefaults { defaults in
            let routineID = UUID()
            let notBefore = try XCTUnwrap(
                Calendar(identifier: .gregorian).date(
                    from: DateComponents(year: 2026, month: 9, day: 21)
                )
            )
            let store = makeTomorrowPromiseStore(defaults: defaults, routineID: routineID)

            store.beginNotificationSetup(
                routineID: routineID,
                reminderMinuteOfDay: 22 * 60,
                notBefore: notBefore,
                originalScheduledStartMinute: nil,
                originalNotificationsEnabled: false
            )

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.pendingNotificationSetup?.routineID, routineID)
            XCTAssertEqual(restored.pendingNotificationSetup?.reminderMinuteOfDay, 22 * 60)
            XCTAssertNil(restored.pendingNotificationSetup?.originalScheduledStartMinute)
            XCTAssertFalse(restored.pendingNotificationSetup?.originalNotificationsEnabled ?? true)
            XCTAssertEqual(restored.notificationNotBefore, notBefore)
            XCTAssertEqual(
                OnboardingStateStore.persistedNotificationNotBefore(
                    for: routineID,
                    defaults: defaults
                ),
                notBefore
            )
        }
    }

    func testRetryingNotificationSetupKeepsTheOriginalRollbackState() {
        withDefaults { defaults in
            let routineID = UUID()
            let store = makeTomorrowPromiseStore(defaults: defaults, routineID: routineID)

            store.beginNotificationSetup(
                routineID: routineID,
                reminderMinuteOfDay: 20 * 60,
                notBefore: Date(timeIntervalSince1970: 100),
                originalScheduledStartMinute: nil,
                originalNotificationsEnabled: false
            )
            store.beginNotificationSetup(
                routineID: routineID,
                reminderMinuteOfDay: 21 * 60,
                notBefore: Date(timeIntervalSince1970: 200),
                originalScheduledStartMinute: 20 * 60,
                originalNotificationsEnabled: true
            )

            XCTAssertEqual(store.pendingNotificationSetup?.reminderMinuteOfDay, 21 * 60)
            XCTAssertEqual(store.pendingNotificationSetup?.notBefore, Date(timeIntervalSince1970: 200))
            XCTAssertNil(store.pendingNotificationSetup?.originalScheduledStartMinute)
            XCTAssertFalse(store.pendingNotificationSetup?.originalNotificationsEnabled ?? true)
        }
    }

    func testAbandoningNotificationSetupClearsPersistedConstraint() {
        withDefaults { defaults in
            let routineID = UUID()
            let store = makeTomorrowPromiseStore(defaults: defaults, routineID: routineID)
            store.beginNotificationSetup(
                routineID: routineID,
                reminderMinuteOfDay: 20 * 60,
                notBefore: Date(timeIntervalSince1970: 100),
                originalScheduledStartMinute: nil,
                originalNotificationsEnabled: false
            )

            store.abandonNotificationSetup()

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertNil(restored.pendingNotificationSetup)
            XCTAssertNil(restored.notificationRoutineID)
            XCTAssertNil(restored.notificationNotBefore)
            XCTAssertNil(restored.draft.reminderMinuteOfDay)
            XCTAssertNil(
                OnboardingStateStore.persistedNotificationNotBefore(
                    for: routineID,
                    defaults: defaults
                )
            )
        }
    }

    private func makeTomorrowPromiseStore(
        defaults: UserDefaults,
        routineID: UUID
    ) -> OnboardingStateStore {
        let store = OnboardingStateStore(defaults: defaults)
        store.beginInAppTutorial(createdRoutineID: routineID)
        store.completeFirstReport(with: .deferred)
        store.completeConversationPrompt(with: .later)
        store.completeStoryUnlockPresentation()
        return store
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
