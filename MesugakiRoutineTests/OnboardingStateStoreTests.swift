import FamilyControls
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
            XCTAssertEqual(store.blockedBehaviorStage, .waitingToPresent)
            XCTAssertEqual(store.confirmationGuidanceStage, .waitingToPresent)
            XCTAssertEqual(store.phase, .dedicatedSetup)
            XCTAssertEqual(store.draft, OnboardingDraft())
            XCTAssertNil(store.createdRoutineID)
            XCTAssertFalse(store.isCompleted)
            XCTAssertFalse(store.isPrologueAutoplayPending)
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
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)

            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.noneID,
                    title: "特にない",
                    iconName: "minus.circle"
                )
            )
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.setupStep, .confirmation)
            XCTAssertEqual(store.confirmationGuidanceStage, .waitingToPresent)
            XCTAssertFalse(store.canContinue())

            completeConfirmationGuidance(store)
            XCTAssertTrue(store.canContinue())
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
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.goalSettingGuidanceStage, .completed)
            XCTAssertEqual(restored.cueSelectionGuidanceStage, .completed)
            XCTAssertEqual(restored.blockedBehaviorStage, .waitingToPresent)
        }
    }

    func testConfirmationGuidancePersistsEachStageAndControlsContinue() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.draft.selectedCueID = "before-bed"
            store.draft.cueText = "寝る前"
            store.goToSetupStep(.confirmation)

            XCTAssertEqual(store.confirmationGuidanceStage, .waitingToPresent)
            XCTAssertFalse(store.canContinue())

            store.presentConfirmationGuidanceIfNeeded()
            XCTAssertEqual(store.confirmationGuidanceStage, .firstMessage)
            XCTAssertFalse(store.canContinue())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.setupStep, .confirmation)
            XCTAssertEqual(store.confirmationGuidanceStage, .firstMessage)
            XCTAssertFalse(store.canContinue())

            store.advanceConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .secondMessage)
            XCTAssertFalse(store.canContinue())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.confirmationGuidanceStage, .secondMessage)
            store.advanceConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .explanation)
            XCTAssertFalse(store.canContinue())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.confirmationGuidanceStage, .explanation)
            store.advanceConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .completed)
            XCTAssertTrue(store.canContinue())

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .confirmation)
            XCTAssertEqual(restored.confirmationGuidanceStage, .completed)
            XCTAssertTrue(restored.canContinue())
            XCTAssertFalse(restored.advanceSetup(), "最終確認後はRoutine保存APIを明示的に呼ぶ")
        }
    }

    func testConfirmationGuidanceRetreatsOneStageAndDismissesFromFirstMessage() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.draft.selectedCueID = "before-bed"
            store.draft.cueText = "寝る前"
            store.goToSetupStep(.confirmation)
            store.presentConfirmationGuidanceIfNeeded()
            store.advanceConfirmationGuidance()
            store.advanceConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .explanation)

            store.retreatConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .secondMessage)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.confirmationGuidanceStage, .secondMessage)
            store.retreatConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .firstMessage)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.confirmationGuidanceStage, .firstMessage)
            store.retreatConfirmationGuidance()
            XCTAssertEqual(store.confirmationGuidanceStage, .completed)
            XCTAssertTrue(store.canContinue())

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.confirmationGuidanceStage, .completed)
            XCTAssertTrue(restored.canContinue())
        }
    }

    func testBlockedBehaviorNoneSelectionSkipsPostSelectionGuidance() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)

            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.noneID,
                    title: "特にない",
                    iconName: "minus.circle"
                )
            )

            XCTAssertTrue(store.canContinue())
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .completed)
            XCTAssertEqual(store.setupStep, .confirmation)

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.draft.blockedBehavior?.selectionID, OnboardingBlockedBehaviorDraft.noneID)
            XCTAssertEqual(restored.blockedBehaviorStage, .completed)
            XCTAssertEqual(restored.setupStep, .confirmation)
        }
    }

    func testBlockedBehaviorSelectionShowsMessagesThenExplanationBeforeConfirmation() {
        withDefaults { defaults in
            var store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: "onboarding-view-social-media",
                    title: "SNSを見る",
                    iconName: "bubble.left.and.bubble.right"
                )
            )

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionFirstMessage)
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionFirstMessage)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionSecondMessage)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .systemExplanation)
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .completed)
            XCTAssertEqual(store.setupStep, .confirmation)
            XCTAssertEqual(store.draft.blockedBehavior?.title, "SNSを見る")
        }
    }

    func testVideoBlockedBehaviorOpensScreenTimeConfigurationAndRequiresTargets() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.screenTimeVideoID,
                    title: "動画をだらだら見る",
                    iconName: "play.rectangle",
                    screenTimeLimitMinutes: 20
                )
            )

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)
            XCTAssertEqual(store.draft.blockedBehavior?.effectiveScreenTimeLimitMinutes, 20)
            XCTAssertEqual(store.draft.blockedBehavior?.screenTimeTargetCount, 0)
            XCTAssertFalse(store.canContinue())
            XCTAssertFalse(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
        }
    }

    func testScreenTimeTargetsAndLimitPersistBeforeAdvancingToGuidance() throws {
        try withDefaults { defaults in
            let selectionData = try makeNonemptyScreenTimeSelectionData()
            var store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.screenTimeVideoID,
                    title: "動画をだらだら見る",
                    iconName: "play.rectangle",
                    screenTimeLimitMinutes: 20
                )
            )
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)

            store.updateBlockedBehaviorScreenTimeConfiguration(
                selectionData: selectionData,
                limitMinutes: 45
            )
            XCTAssertTrue(store.canContinue())

            store = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
            XCTAssertEqual(store.draft.blockedBehavior?.screenTimeSelectionData, selectionData)
            XCTAssertEqual(store.draft.blockedBehavior?.effectiveScreenTimeLimitMinutes, 45)
            XCTAssertEqual(store.draft.blockedBehavior?.screenTimeTargetCount, 1)
            XCTAssertTrue(store.canContinue())

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionFirstMessage)
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)
        }
    }

    func testScreenTimeConfigurationBackNavigationReturnsToSelectionAndGuidanceReturnsToConfiguration() throws {
        try withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.screenTimeVideoID,
                    title: "動画をだらだら見る",
                    iconName: "play.rectangle"
                )
            )

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .awaitingSelection)
            XCTAssertEqual(
                store.draft.blockedBehavior?.selectionID,
                OnboardingBlockedBehaviorDraft.screenTimeVideoID
            )

            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
            store.updateBlockedBehaviorScreenTimeConfiguration(
                selectionData: try makeNonemptyScreenTimeSelectionData(),
                limitMinutes: 30
            )
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionFirstMessage)

            XCTAssertTrue(store.retreatSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .screenTimeConfiguration)
            XCTAssertTrue(store.canContinue())
        }
    }

    func testEmptyCustomBlockedBehaviorCannotContinue() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.customID,
                    title: "  \n ",
                    iconName: "pencil"
                )
            )

            XCTAssertFalse(store.canContinue())
            XCTAssertFalse(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .awaitingSelection)
            XCTAssertEqual(store.setupStep, .blockedBehaviorSelection)

            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.customID,
                    title: "ゲームをだらだらする",
                    iconName: "pencil"
                )
            )
            XCTAssertTrue(store.canContinue())
            XCTAssertTrue(store.advanceSetup())
            XCTAssertEqual(store.blockedBehaviorStage, .postSelectionFirstMessage)
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
                legacySnapshot.removeValue(forKey: "blockedBehaviorStage")
                legacySnapshot.removeValue(forKey: "confirmationGuidanceStage")
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
                    step.orderIndex > OnboardingSetupStep.goalSetting.orderIndex
                        ? .completed : .waitingToPresent
                )
                XCTAssertEqual(
                    restored.cueSelectionGuidanceStage,
                    step.orderIndex > OnboardingSetupStep.cueSelection.orderIndex
                        ? .completed : .waitingToPresent
                )
                XCTAssertEqual(
                    restored.blockedBehaviorStage,
                    step == .confirmation ? .completed : .waitingToPresent
                )
                XCTAssertEqual(restored.confirmationGuidanceStage, .waitingToPresent)
                XCTAssertEqual(restored.draft.userName, "かずし")
                XCTAssertEqual(restored.draft.selectedHabitID, "onboarding-read")
            }
        }
    }

    func testLegacyConfirmationRawValueFourStillRestoresAsConfirmation() throws {
        try withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            store.draft.selectedHabitID = "onboarding-read-book"
            store.draft.habitTitle = "本を読む"
            store.draft.habitIconName = "book"
            store.draft.selectedGoalID = "page-1"
            store.draft.goalText = "1ページ"
            store.draft.routineTitle = "本を1ページ読む"
            store.draft.selectedCueID = "before-sleep"
            store.draft.cueText = "寝る前"
            store.goToSetupStep(.confirmation)

            let data = try XCTUnwrap(
                defaults.data(forKey: OnboardingStateStore.defaultStorageKey)
            )
            var legacySnapshot = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertEqual(legacySnapshot["setupStep"] as? Int, 4)
            legacySnapshot["goalSettingGuidanceStage"] = "completed"
            legacySnapshot["cueSelectionGuidanceStage"] = "completed"
            legacySnapshot.removeValue(forKey: "blockedBehaviorStage")
            legacySnapshot.removeValue(forKey: "confirmationGuidanceStage")
            if var draft = legacySnapshot["draft"] as? [String: Any] {
                draft.removeValue(forKey: "blockedBehavior")
                legacySnapshot["draft"] = draft
            }
            defaults.set(
                try JSONSerialization.data(withJSONObject: legacySnapshot),
                forKey: OnboardingStateStore.defaultStorageKey
            )

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .confirmation)
            XCTAssertEqual(restored.setupStep.rawValue, 4)
            XCTAssertEqual(restored.blockedBehaviorStage, .completed)
            XCTAssertEqual(restored.confirmationGuidanceStage, .waitingToPresent)
            XCTAssertFalse(restored.canContinue())
            XCTAssertNil(restored.draft.blockedBehavior)

            restored.goToSetupStep(.habitSelection)
            XCTAssertTrue(restored.advanceSetup())
            XCTAssertTrue(restored.advanceSetup())
            XCTAssertTrue(restored.advanceSetup())
            XCTAssertEqual(restored.setupStep, .blockedBehaviorSelection)
            XCTAssertEqual(restored.blockedBehaviorStage, .waitingToPresent)
        }
    }

    func testOlderManualBlockedBehaviorDraftWithoutScreenTimeFieldsStillRestores() throws {
        try withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.blockedBehaviorSelection)
            finishBlockedBehaviorIntroduction(store)
            store.selectBlockedBehavior(
                OnboardingBlockedBehaviorDraft(
                    selectionID: "onboarding-view-social-media",
                    title: "SNSを見る",
                    iconName: "bubble.left.and.bubble.right"
                )
            )

            let data = try XCTUnwrap(
                defaults.data(forKey: OnboardingStateStore.defaultStorageKey)
            )
            var legacySnapshot = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            var draft = try XCTUnwrap(legacySnapshot["draft"] as? [String: Any])
            var blockedBehavior = try XCTUnwrap(
                draft["blockedBehavior"] as? [String: Any]
            )
            blockedBehavior.removeValue(forKey: "screenTimeLimitMinutes")
            blockedBehavior.removeValue(forKey: "screenTimeSelectionData")
            draft["blockedBehavior"] = blockedBehavior
            legacySnapshot["draft"] = draft
            defaults.set(
                try JSONSerialization.data(withJSONObject: legacySnapshot),
                forKey: OnboardingStateStore.defaultStorageKey
            )

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .blockedBehaviorSelection)
            XCTAssertEqual(restored.blockedBehaviorStage, .awaitingSelection)
            XCTAssertEqual(restored.draft.blockedBehavior?.selectionID, "onboarding-view-social-media")
            XCTAssertEqual(restored.draft.blockedBehavior?.title, "SNSを見る")
            XCTAssertNil(restored.draft.blockedBehavior?.screenTimeLimitMinutes)
            XCTAssertNil(restored.draft.blockedBehavior?.screenTimeSelectionData)
            XCTAssertTrue(restored.canContinue())
        }
    }

    func testLaterSetupScreensStillRetreatOneScreenAtATime() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.goToSetupStep(.confirmation)

            let steps: [OnboardingSetupStep] = [
                .blockedBehaviorSelection, .cueSelection, .goalSetting, .habitSelection,
            ]
            for step in steps {
                XCTAssertTrue(store.retreatSetup())
                XCTAssertEqual(store.setupStep, step)
                XCTAssertEqual(OnboardingStateStore(defaults: defaults).setupStep, step)
                if step == .blockedBehaviorSelection {
                    XCTAssertEqual(
                        store.draft.blockedBehavior?.selectionID,
                        OnboardingBlockedBehaviorDraft.noneID
                    )
                    XCTAssertTrue(store.canContinue())
                }
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
            XCTAssertEqual(first.phase, .prologue)
            XCTAssertTrue(first.isPrologueAutoplayPending)

            first.completePrologue()
            XCTAssertEqual(first.phase, .prologueMessage)
            XCTAssertFalse(first.isPrologueAutoplayPending)

            first.completePrologueMessage()
            XCTAssertEqual(first.phase, .firstReport)
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
            XCTAssertFalse(completed.isPrologueAutoplayPending)
        }
    }

    func testProloguePhasesPersistAcrossRestarts() {
        withDefaults { defaults in
            let routineID = UUID()
            let setup = OnboardingStateStore(defaults: defaults)

            setup.beginInAppTutorial(createdRoutineID: routineID)

            let prologue = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(prologue.createdRoutineID, routineID)
            XCTAssertEqual(prologue.phase, .prologue)
            XCTAssertTrue(prologue.isPrologueAutoplayPending)

            prologue.completePrologue()

            let message = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(message.createdRoutineID, routineID)
            XCTAssertEqual(message.phase, .prologueMessage)
            XCTAssertFalse(message.isPrologueAutoplayPending)

            message.completePrologueMessage()

            let firstReport = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(firstReport.createdRoutineID, routineID)
            XCTAssertEqual(firstReport.phase, .firstReport)
            XCTAssertFalse(firstReport.isPrologueAutoplayPending)
        }
    }

    func testCompletedLegacySnapshotWithoutPrologueAutoplayFieldDoesNotAutoplay() throws {
        try withDefaults { defaults in
            let store = makeTomorrowPromiseStore(defaults: defaults, routineID: UUID())
            store.completeOnboarding(notificationChoice: .notNow)

            let data = try XCTUnwrap(
                defaults.data(forKey: OnboardingStateStore.defaultStorageKey)
            )
            var legacySnapshot = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            legacySnapshot.removeValue(forKey: "isPrologueAutoplayPending")
            defaults.set(
                try JSONSerialization.data(withJSONObject: legacySnapshot),
                forKey: OnboardingStateStore.defaultStorageKey
            )

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertTrue(restored.isCompleted)
            XCTAssertFalse(restored.isPrologueAutoplayPending)
        }
    }

    func testOutOfOrderPhaseMutationsAreIgnored() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)

            store.completePrologue()
            store.completePrologueMessage()
            store.completeFirstReport(with: .completed)
            store.completeConversationPrompt(with: .started)
            store.completeStoryUnlockPresentation()
            store.completeOnboarding(notificationChoice: .notNow)

            XCTAssertEqual(store.phase, .dedicatedSetup)
            XCTAssertNil(store.firstReportOutcome)
            XCTAssertNil(store.conversationChoice)
            XCTAssertNil(store.notificationChoice)
            XCTAssertFalse(store.isCompleted)

            store.beginInAppTutorial(createdRoutineID: UUID())
            store.completePrologueMessage()
            store.completeOnboarding(notificationChoice: .notNow)

            XCTAssertEqual(store.phase, .prologue)
            XCTAssertTrue(store.isPrologueAutoplayPending)
            XCTAssertNil(store.notificationChoice)

            store.completePrologue()
            store.completePrologue()
            store.completeFirstReport(with: .completed)
            store.completeOnboarding(notificationChoice: .notNow)

            XCTAssertEqual(store.phase, .prologueMessage)
            XCTAssertFalse(store.isPrologueAutoplayPending)
            XCTAssertNil(store.firstReportOutcome)
            XCTAssertNil(store.notificationChoice)
            XCTAssertFalse(store.isCompleted)

            store.completePrologueMessage()
            store.completePrologue()

            XCTAssertEqual(store.phase, .firstReport)
            XCTAssertFalse(store.isPrologueAutoplayPending)
        }
    }

    func testResetClearsPersistedProgressAndDraft() {
        withDefaults { defaults in
            let store = OnboardingStateStore(defaults: defaults)
            store.draft.userName = "かずし"
            XCTAssertTrue(store.advanceSetup())
            store.beginInAppTutorial(createdRoutineID: UUID())
            store.completePrologue()
            store.completePrologueMessage()
            store.completeFirstReport(with: .completed)

            store.reset()

            let restored = OnboardingStateStore(defaults: defaults)
            XCTAssertEqual(restored.setupStep, .introduction)
            XCTAssertEqual(restored.introductionStage, .appIntroduction)
            XCTAssertEqual(restored.habitSelectionStage, .awaitingSelection)
            XCTAssertEqual(restored.goalSettingGuidanceStage, .waitingToPresent)
            XCTAssertEqual(restored.cueSelectionGuidanceStage, .waitingToPresent)
            XCTAssertEqual(restored.blockedBehaviorStage, .waitingToPresent)
            XCTAssertEqual(restored.confirmationGuidanceStage, .waitingToPresent)
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
            XCTAssertFalse(store.isPrologueAutoplayPending)
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
            store.completePrologue()
            store.completePrologueMessage()

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
            store.completePrologue()
            store.completePrologueMessage()

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
        store.completePrologue()
        store.completePrologueMessage()
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

    private func completeConfirmationGuidance(
        _ store: OnboardingStateStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        store.presentConfirmationGuidanceIfNeeded()
        XCTAssertEqual(store.confirmationGuidanceStage, .firstMessage, file: file, line: line)
        store.advanceConfirmationGuidance()
        XCTAssertEqual(store.confirmationGuidanceStage, .secondMessage, file: file, line: line)
        store.advanceConfirmationGuidance()
        XCTAssertEqual(store.confirmationGuidanceStage, .explanation, file: file, line: line)
        store.advanceConfirmationGuidance()
        XCTAssertEqual(store.confirmationGuidanceStage, .completed, file: file, line: line)
    }

    private func finishBlockedBehaviorIntroduction(
        _ store: OnboardingStateStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        store.presentBlockedBehaviorGuidanceIfNeeded()
        XCTAssertEqual(store.blockedBehaviorStage, .firstMessage, file: file, line: line)
        XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        XCTAssertEqual(store.blockedBehaviorStage, .secondMessage, file: file, line: line)
        XCTAssertTrue(store.advanceSetup(), file: file, line: line)
        XCTAssertEqual(store.blockedBehaviorStage, .awaitingSelection, file: file, line: line)
        XCTAssertEqual(store.setupStep, .blockedBehaviorSelection, file: file, line: line)
    }

    private func makeNonemptyScreenTimeSelectionData() throws -> Data {
        let encodedSelection = Data(
            #"{"untokenizedCategoryIdentifiers":[],"categoryTokens":[],"webDomainTokens":[],"untokenizedApplicationIdentifiers":[],"applicationTokens":[{"data":"AQID"}],"untokenizedWebDomainIdentifiers":[],"includeEntireCategory":false}"#.utf8
        )
        let selection = try JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: encodedSelection
        )
        XCTAssertEqual(selection.applicationTokens.count, 1)
        return try JSONEncoder().encode(selection)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
