import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class RoutinePresetTests: XCTestCase {
    private var container: ModelContainer?

    func testCatalogUsesUniqueIdentifiersAndAvailableIcons() {
        XCTAssertFalse(RoutinePreset.all.isEmpty)
        XCTAssertEqual(Set(RoutinePreset.all.map(\.id)).count, RoutinePreset.all.count)
        XCTAssertEqual(Set(RoutinePreset.all.map(\.title)).count, RoutinePreset.all.count)

        for preset in RoutinePreset.all {
            XCTAssertTrue(RoutineIcon.all.contains(preset.iconName), preset.iconName)
            XCTAssertFalse(preset.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(preset.targetCount, 1)
        }

        XCTAssertTrue(RoutinePreset.recommended.allSatisfy { $0.targetDurationMinutes == nil })
        XCTAssertTrue(RoutinePreset.timer.allSatisfy { ($0.targetDurationMinutes ?? 0) > 0 })
    }

    func testTimerCatalogContainsRequestedInitialPresets() {
        XCTAssertEqual(
            RoutinePreset.timer.map(\.title),
            ["本を読む", "整頓をする", "運動する", "瞑想をする"]
        )
        XCTAssertTrue(RoutinePreset.timer.allSatisfy { $0.targetDurationMinutes == 10 })
    }

    func testRecommendedCatalogContainsOnlyRequestedPresetsInDisplayOrder() {
        XCTAssertEqual(
            RoutinePreset.recommended.map(\.title),
            [
                "筋トレをする",
                "散歩をする",
                "ストレッチをする",
                "日記を書く",
                "勉強する",
                "片づける",
                "ビタミンを飲む",
            ]
        )
    }

    func testOnboardingCatalogIsSeparateAndContainsRequestedPresets() {
        XCTAssertEqual(
            RoutinePreset.onboarding.map(\.title),
            [
                "筋トレをする",
                "散歩をする",
                "勉強する",
                "日記をつける",
                "本を読む",
                "部屋を片付ける",
            ]
        )
        XCTAssertEqual(
            Set(RoutinePreset.onboarding.map(\.id)).count,
            RoutinePreset.onboarding.count
        )
        XCTAssertTrue(
            RoutinePreset.onboarding.allSatisfy {
                RoutineIcon.all.contains($0.iconName) && $0.targetDurationMinutes == nil
            }
        )
        XCTAssertTrue(
            Set(RoutinePreset.onboarding.map(\.id))
                .isDisjoint(with: Set(RoutinePreset.all.map(\.id)))
        )
    }

    func testApplyingPresetFillsNewRoutineDraftAndRestoresSafeDefaults() {
        let preset = RoutinePreset(
            id: "test",
            title: "週に3回運動する",
            iconName: "figure.run",
            period: .week,
            targetCount: 3
        )
        let viewModel = RoutineEditViewModel(routine: nil)
        viewModel.title = "変更前"
        viewModel.cueText = "寝る前"
        viewModel.notifyAtScheduledTime = true
        viewModel.selectedWeekdays = [Weekday.monday.rawValue]

        viewModel.applyPreset(preset)

        XCTAssertEqual(viewModel.title, preset.title)
        XCTAssertEqual(viewModel.cueText, "")
        XCTAssertEqual(viewModel.iconName, preset.iconName)
        XCTAssertEqual(viewModel.period, .week)
        XCTAssertEqual(viewModel.targetCount, 3)
        XCTAssertNil(viewModel.targetDurationMinutes)
        XCTAssertFalse(viewModel.notifyAtScheduledTime)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allWeekdayValues))
    }

    func testCustomSelectionClearsValuesFromPreviouslySelectedPreset() {
        let viewModel = RoutineEditViewModel(routine: nil)
        viewModel.applyPreset(RoutinePreset.timer[0])
        viewModel.period = .month
        viewModel.targetCount = 8
        viewModel.cueText = "朝ごはんの後"
        viewModel.notifyAtScheduledTime = true

        viewModel.prepareCustomRoutine()

        XCTAssertEqual(viewModel.title, "")
        XCTAssertEqual(viewModel.cueText, "")
        XCTAssertNil(viewModel.iconName)
        XCTAssertEqual(viewModel.period, .day)
        XCTAssertEqual(viewModel.targetCount, 1)
        XCTAssertNil(viewModel.targetDurationMinutes)
        XCTAssertFalse(viewModel.notifyAtScheduledTime)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allWeekdayValues))
    }

    func testApplyingTimerPresetSetsTargetDurationAndRecommendedClearsIt() {
        let viewModel = RoutineEditViewModel(routine: nil)

        viewModel.applyPreset(RoutinePreset.timer[0])

        XCTAssertEqual(viewModel.title, "本を読む")
        XCTAssertEqual(viewModel.targetDurationMinutes, 10)

        viewModel.applyPreset(RoutinePreset.recommended[0])

        XCTAssertNil(viewModel.targetDurationMinutes)
    }

    func testApplyingPresetDoesNotOverwriteExistingRoutine() {
        let routine = Routine(title: "既存の約束", cueText: "寝る前", iconName: "star")
        let viewModel = RoutineEditViewModel(routine: routine)

        viewModel.applyPreset(RoutinePreset.all[0])

        XCTAssertEqual(viewModel.title, "既存の約束")
        XCTAssertEqual(viewModel.cueText, "寝る前")
        XCTAssertEqual(viewModel.iconName, "star")
    }

    func testCueTextIsNormalizedPersistedRestoredAndCleared() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let createViewModel = RoutineEditViewModel(routine: nil)
        createViewModel.configure(context: context)
        createViewModel.title = "本を1ページ読む"
        createViewModel.cueText = "  寝る前\n"

        XCTAssertTrue(createViewModel.save())

        var verificationContext = ModelContext(container)
        var savedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first
        )
        XCTAssertEqual(savedRoutine.cueText, "寝る前")

        let editViewModel = RoutineEditViewModel(routine: savedRoutine)
        XCTAssertEqual(editViewModel.cueText, "寝る前")
        editViewModel.configure(context: verificationContext)
        editViewModel.cueText = "  \n"

        XCTAssertTrue(editViewModel.save())

        verificationContext = ModelContext(container)
        savedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first
        )
        XCTAssertNil(savedRoutine.cueText)
    }

    func testDataSeederLeavesFreshRoutineStoreEmpty() throws {
        let container = try makeContainer()

        DataSeeder.seedIfNeeded(context: container.mainContext)

        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<Routine>()).isEmpty
        )
    }

    func testPresetIsNotPersistedUntilSaveAndRepeatedSaveDoesNotDuplicateIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = RoutineEditViewModel(routine: nil)
        let preset = RoutinePreset.all[0]
        viewModel.configure(context: context)

        viewModel.applyPreset(preset)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
        XCTAssertTrue(viewModel.save())

        var savedRoutines = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(savedRoutines.count, 1)
        XCTAssertEqual(savedRoutines[0].title, preset.title)
        XCTAssertEqual(savedRoutines[0].iconName, preset.iconName)

        XCTAssertTrue(viewModel.save())
        savedRoutines = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(savedRoutines.count, 1)
    }

    func testTimerTargetDurationIsPersistedAndRestoredForEditing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = RoutineEditViewModel(routine: nil)
        viewModel.configure(context: context)
        viewModel.applyPreset(RoutinePreset.timer[0])
        viewModel.targetDurationMinutes = 25

        XCTAssertTrue(viewModel.save())

        let verificationContext = ModelContext(container)
        let savedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first
        )
        XCTAssertEqual(savedRoutine.targetDurationMinutes, 25)

        let editViewModel = RoutineEditViewModel(routine: savedRoutine)
        XCTAssertEqual(editViewModel.targetDurationMinutes, 25)
    }

    func testTimerSessionUsesDeadlineAndCompletesOnlyOnce() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RoutineTimerSession(targetMinutes: 1, now: start)

        XCTAssertEqual(session.displayedRemainingSeconds, 60)
        XCTAssertEqual(session.remainingFraction, 1, accuracy: 0.0001)
        XCTAssertNil(session.refresh(now: start.addingTimeInterval(3)))
        XCTAssertEqual(session.displayedRemainingSeconds, 57)
        XCTAssertEqual(session.remainingFraction, 0.95, accuracy: 0.0001)

        let expectedCompletion = start.addingTimeInterval(60)
        XCTAssertEqual(session.refresh(now: start.addingTimeInterval(90)), expectedCompletion)
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(session.displayedRemainingSeconds, 0)
        XCTAssertNil(session.refresh(now: start.addingTimeInterval(120)))
    }

    func testTimerSessionPauseExcludesPausedTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RoutineTimerSession(targetMinutes: 1, now: start)

        XCTAssertNil(session.pause(now: start.addingTimeInterval(20)))
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.displayedRemainingSeconds, 40)
        XCTAssertNil(session.refresh(now: start.addingTimeInterval(200)))
        XCTAssertEqual(session.displayedRemainingSeconds, 40)

        session.resume(now: start.addingTimeInterval(200))
        XCTAssertEqual(session.phase, .running)
        XCTAssertNil(session.refresh(now: start.addingTimeInterval(225)))
        XCTAssertEqual(session.displayedRemainingSeconds, 15)
        XCTAssertEqual(
            session.refresh(now: start.addingTimeInterval(240)),
            start.addingTimeInterval(240)
        )
    }

    func testTimerSessionStopPreventsLaterCompletion() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RoutineTimerSession(targetMinutes: 1, now: start)

        XCTAssertNil(session.refresh(now: start.addingTimeInterval(20)))
        session.stop()

        XCTAssertEqual(session.phase, .stopped)
        XCTAssertEqual(session.displayedRemainingSeconds, 40)
        XCTAssertNil(session.refresh(now: start.addingTimeInterval(120)))
        XCTAssertNil(session.completedAt)
    }

    func testTimerDurationFormattingAlwaysShowsHoursMinutesAndSeconds() {
        XCTAssertEqual(RoutineTimerSession.formattedDuration(seconds: 0), "00:00:00")
        XCTAssertEqual(RoutineTimerSession.formattedDuration(seconds: 57), "00:00:57")
        XCTAssertEqual(RoutineTimerSession.formattedDuration(seconds: 600), "00:10:00")
        XCTAssertEqual(RoutineTimerSession.formattedDuration(seconds: 3_661), "01:01:01")
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
