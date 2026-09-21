import XCTest
@testable import MesugakiRoutine

@MainActor
final class OnboardingStateStoreTests: XCTestCase {
    func testNewStoreStartsAtFirstDedicatedScreen() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertEqual(store.setupStep, .introduction)
            XCTAssertEqual(store.introductionStage, .appIntroduction)
            XCTAssertEqual(store.habitSelectionStage, .awaitingSelection)
            XCTAssertEqual(store.goalSettingGuidanceStage, .waitingToPresent)
            XCTAssertEqual(store.cueSelectionGuidanceStage, .waitingToPresent)
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
            first.draft.selectedHabitID = "onboarding-read"
            first.draft.habitTitle = "本を読む"
            first.draft.habitIconName = "book"

            finishIntroduction(first)
            XCTAssertEqual(first.setupStep, .habitSelection)
            finishHabitSelectionIntroduction(first)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .goalSetting)
            XCTAssertEqual(restored.draft.userName, "かずし")
            XCTAssertEqual(restored.draft.selectedHabitID, "onboarding-read")
            XCTAssertEqual(restored.draft.habitTitle, "本を読む")
            XCTAssertEqual(restored.draft.habitIconName, "book")
        }
    }

    func testSetupCannotAdvanceUntilCurrentInputIsValid() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.introductionStage, .nameEntry)
            XCTAssertFalse(store.advanceSetup())
            store.draft.userName = "  "
            XCTAssertFalse(store.advanceSetup())
            XCTAssertEqual(store.introductionStage, .nameEntry)
            XCTAssertEqual(store.setupStep, .introduction)

            store.draft.userName = "かずし"
            finishIntroduction(store)

            store.draft.habitTitle = "本を読む"
            XCTAssertFalse(store.advanceSetup(), "選択IDのないタイトルだけでは進めない")
            store.draft.selectedHabitID = "onboarding-read"
            finishHabitSelectionIntroduction(store)

            store.draft.selectedGoalID = "one-page"
            store.draft.routineTitle = "本を1ページ読む"
            completeDelayedGuidance(store, for: .goalSetting)
            XCTAssertTrue(store.advanceSetup())

            store.draft.selectedCueID = "before-bed"
            store.draft.cueText = "寝る前"
            completeDelayedGuidance(store, for: .cueSelection)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .confirmation)
            XCTAssertFalse(store.advanceSetup(), "最終確認後はRoutine保存APIを明示的に呼ぶ")
        }
    }

    func testIntroductionProgressResumesAtEachMessageWithoutLeavingFirstScreen() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"

            let stages: [OnboardingIntroductionStage] = [
                .nameEntry, .firstMessage, .secondMessage, .characterExplanation,
            ]
            for stage in stages {
                XCTAssertTrue(store.advanceSetup())
                XCTAssertEqual(store.introductionStage, stage)
                XCTAssertEqual(store.setupStep, .introduction)

                store = OnboardingStateStore(defaults: defaults)
                XCTAssertEqual(store.introductionStage, stage)
                XCTAssertEqual(store.setupStep, .introduction)
                XCTAssertEqual(store.draft.userName, "かずし")
                XCTAssertNil(store.createdRoutineID)
                XCTAssertFalse(store.isCompleted)
            }

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .habitSelection)
            XCTAssertEqual(OnboardingStateStore(defaults: defaults).setupStep, .habitSelection)
        }
    }

    func testRetreatWithinIntroductionReturnsOneStageAtATime() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            XCTAssertTrue(store.advanceSetup())
            XCTAssertTrue(store.advanceSetup())
            XCTAssertTrue(store.advanceSetup())
            XCTAssertTrue(store.advanceSetup())

            let stages: [OnboardingIntroductionStage] = [
                .secondMessage, .firstMessage, .nameEntry, .appIntroduction,
            ]
            for stage in stages {
                XCTAssertTrue(store.retreatSetup())
                XCTAssertEqual(store.introductionStage, stage)
                XCTAssertEqual(store.setupStep, .introduction)
                XCTAssertEqual(OnboardingStateStore(defaults: defaults).introductionStage, stage)
            }
            XCTAssertFalse(store.retreatSetup())
            XCTAssertEqual(store.draft.userName, "かずし")
        }
    }

    func testHabitSelectionIntroductionPersistsAndAdvancesOneStageAtATime() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "onboarding-read"
            store.draft.habitTitle = "本を読む"

            store.beginHabitSelectionIntroductionIfNeeded()
            XCTAssertEqual(store.habitSelectionStage, .firstMessage)
            XCTAssertEqual(store.setupStep, .habitSelection)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.habitSelectionStage, .firstMessage)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .secondMessage)
            XCTAssertEqual(store.setupStep, .habitSelection)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.habitSelectionStage, .secondMessage)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .systemExplanation)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.habitSelectionStage, .systemExplanation)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .completed)
            XCTAssertEqual(store.setupStep, .goalSetting)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.habitSelectionStage, .completed)
            XCTAssertEqual(restored.setupStep, .goalSetting)
        }
    }

    func testCustomHabitShowsExplanationBeforeRequiringItsTitle() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "custom"

            store.beginHabitSelectionIntroductionIfNeeded()
            XCTAssertEqual(store.habitSelectionStage, .firstMessage)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .secondMessage)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .systemExplanation)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .completed)
            XCTAssertEqual(store.setupStep, .habitSelection)
            XCTAssertFalse(store.advanceSetup())

            store.draft.habitTitle = "ストレッチする"
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .goalSetting)
        }
    }

    func testHabitSelectionIntroductionRetreatsToSelectionAndDoesNotReplayAfterGoal() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "onboarding-read"
            store.draft.habitTitle = "本を読む"
            store.beginHabitSelectionIntroductionIfNeeded()
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.habitSelectionStage, .secondMessage)
            XCTAssertTrue(store.advanceSetup())

            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.habitSelectionStage, .secondMessage)
            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.habitSelectionStage, .firstMessage)
            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.habitSelectionStage, .awaitingSelection)
            XCTAssertEqual(store.setupStep, .habitSelection)

            finishHabitSelectionIntroduction(store)
            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.setupStep, .habitSelection)
            XCTAssertEqual(store.habitSelectionStage, .completed)
        }
    }

    func testDelayedGuidancePersistsAndBlocksAdvancingUntilDismissed() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "onboarding-read"
            store.draft.habitTitle = "本を読む"
            finishHabitSelectionIntroduction(store)
            store.draft.selectedGoalID = "one-page"
            store.draft.routineTitle = "本を1ページ読む"

            XCTAssertEqual(store.goalSettingGuidanceStage, .waitingToPresent)
            XCTAssertFalse(store.advanceSetup())

            store.presentDelayedGuidanceIfNeeded(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .presented)
            XCTAssertFalse(store.advanceSetup())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.setupStep, .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .presented)

            store.advanceDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .explanation)
            XCTAssertFalse(store.advanceSetup())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.setupStep, .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .explanation)

            store.retreatDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .presented)
            store.advanceDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .explanation)
            store.advanceDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .completed)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .cueSelection)

            store.draft.selectedCueID = "before-bed"
            store.draft.cueText = "寝る前"
            XCTAssertFalse(store.advanceSetup())
            completeDelayedGuidance(store, for: .cueSelection)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .confirmation)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.goalSettingGuidanceStage, .completed)
            XCTAssertEqual(restored.cueSelectionGuidanceStage, .completed)
        }
    }

    func testDelayedGuidanceBackNavigationReturnsOneStageAtATime() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "onboarding-read"
            store.draft.habitTitle = "本を読む"
            finishHabitSelectionIntroduction(store)

            store.presentDelayedGuidanceIfNeeded(for: .goalSetting)
            store.advanceDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .explanation)

            store.retreatDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .presented)
            XCTAssertEqual(store.setupStep, .goalSetting)

            store.retreatDelayedGuidance(for: .goalSetting)
            XCTAssertEqual(store.goalSettingGuidanceStage, .completed)
            XCTAssertEqual(store.setupStep, .goalSetting)
        }
    }

    func testReturningFromHabitSelectionAllowsNameEditingAndReplaysIntroduction() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            finishIntroduction(store)
            store.draft.selectedHabitID = "onboarding-read"
            store.draft.habitTitle = "本を読む"

            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.setupStep, .introduction)
            XCTAssertEqual(store.introductionStage, .nameEntry)
            XCTAssertEqual(store.draft.userName, "かずし")
            XCTAssertEqual(store.draft.selectedHabitID, "onboarding-read")

            store.draft.userName = " "
            XCTAssertFalse(store.advanceSetup())
            store.draft.userName = "新しい名前"
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .introduction)
            XCTAssertEqual(store.introductionStage, .firstMessage)
            XCTAssertEqual(OnboardingStateStore(defaults: defaults).draft.userName, "新しい名前")
        }
    }

    func testDirectNavigationToIntroductionResetsItsStageButPreservesDraft() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            XCTAssertTrue(store.advanceSetup())
            XCTAssertTrue(store.advanceSetup())

            store.goToSetupStep(.introduction)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.introductionStage, .nameEntry)
            XCTAssertEqual(restored.setupStep, .introduction)
            XCTAssertEqual(restored.draft.userName, "かずし")
        }
    }

    func testOlderSnapshotWithoutIntroductionStagePreservesExistingProgress() throws {
        try withDefaults { defaults in
            let first = OnboardingStateStore(defaults: defaults)
            first.draft.userName = "かずし"
            first.draft.selectedHabitID = "onboarding-read"
            first.draft.habitTitle = "本を読む"

            let steps: [OnboardingSetupStep] = [
                .introduction, .habitSelection, .goalSetting, .cueSelection, .confirmation,
            ]
            for step in steps {
                first.goToSetupStep(step)
                let data = try XCTUnwrap(defaults.data(forKey: OnboardingStateStore.defaultStorageKey))
                var legacySnapshot = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                legacySnapshot.removeValue(forKey: "introductionStage")
                legacySnapshot.removeValue(forKey: "habitSelectionStage")
                legacySnapshot.removeValue(forKey: "goalSettingGuidanceStage")
                legacySnapshot.removeValue(forKey: "cueSelectionGuidanceStage")
                defaults.set(
                    try JSONSerialization.data(withJSONObject: legacySnapshot),
                    forKey: OnboardingStateStore.defaultStorageKey
                )

                let restored = OnboardingStateStore(defaults: defaults)
                XCTAssertFalse(restored.startedWithoutSavedState)
                XCTAssertEqual(restored.setupStep, step)
                XCTAssertEqual(restored.introductionStage, .nameEntry)
                let expectedHabitStage: OnboardingHabitSelectionStage = switch step {
                case .introduction: .awaitingSelection
                case .habitSelection: .firstMessage
                default: .completed
                }
                XCTAssertEqual(restored.habitSelectionStage, expectedHabitStage)
                XCTAssertEqual(
                    restored.goalSettingGuidanceStage,
                    step.rawValue > OnboardingSetupStep.goalSetting.rawValue
                        ? .completed : .waitingToPresent
                )
                XCTAssertEqual(
                    restored.cueSelectionGuidanceStage,
                    step.rawValue > OnboardingSetupStep.cueSelection.rawValue
                        ? .completed : .waitingToPresent
                )
                XCTAssertEqual(restored.draft.userName, "かずし")
                XCTAssertEqual(restored.draft.selectedHabitID, "onboarding-read")
            }
        }
    }

    func testLaterSetupScreensStillRetreatOneScreenAtATime() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.confirmation)

            let steps: [OnboardingSetupStep] = [.cueSelection, .goalSetting, .habitSelection]
            for step in steps {
                XCTAssertTrue(store.retreatSetup())
                XCTAssertEqual(store.setupStep, step)
                XCTAssertEqual(OnboardingStateStore(defaults: defaults).setupStep, step)
            }
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
            XCTAssertTrue(store.advanceSetup())
            store.beginInAppTutorial(createdRoutineID: UUID())
            store.completeFirstReport(with: .completed)

            store.reset()

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .introduction)
            XCTAssertEqual(restored.introductionStage, .appIntroduction)
            XCTAssertEqual(restored.habitSelectionStage, .awaitingSelection)
            XCTAssertEqual(restored.goalSettingGuidanceStage, .waitingToPresent)
            XCTAssertEqual(restored.cueSelectionGuidanceStage, .waitingToPresent)
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

    private func finishIntroduction(
        _ store: OnboardingStateStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let remainingAdvances: Int
        switch store.introductionStage {
        case .appIntroduction:
            remainingAdvances = 5
        case .nameEntry:
            remainingAdvances = 4
        case .firstMessage:
            remainingAdvances = 3
        case .secondMessage:
            remainingAdvances = 2
        case .characterExplanation:
            remainingAdvances = 1
        }

        for _ in 0..<remainingAdvances {
            XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        }
        XCTAssertEqual(store.setupStep, .habitSelection, file: file, line: line)
    }

    private func finishHabitSelectionIntroduction(
        _ store: OnboardingStateStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        store.beginHabitSelectionIntroductionIfNeeded()
        XCTAssertEqual(store.habitSelectionStage, .firstMessage, file: file, line: line)
        XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        XCTAssertEqual(store.habitSelectionStage, .secondMessage, file: file, line: line)
        XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        XCTAssertEqual(store.habitSelectionStage, .systemExplanation, file: file, line: line)
        XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        XCTAssertEqual(store.habitSelectionStage, .completed, file: file, line: line)
        XCTAssertEqual(store.setupStep, .goalSetting, file: file, line: line)
    }

    private func completeDelayedGuidance(
        _ store: OnboardingStateStore,
        for step: OnboardingSetupStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        store.presentDelayedGuidanceIfNeeded(for: step)
        XCTAssertEqual(store.delayedGuidanceStage(for: step), .presented, file: file, line: line)
        store.advanceDelayedGuidance(for: step)
        XCTAssertEqual(store.delayedGuidanceStage(for: step), .explanation, file: file, line: line)
        store.advanceDelayedGuidance(for: step)
        XCTAssertEqual(store.delayedGuidanceStage(for: step), .completed, file: file, line: line)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
