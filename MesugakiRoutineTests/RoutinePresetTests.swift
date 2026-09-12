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
        viewModel.notifyAtScheduledTime = true
        viewModel.selectedWeekdays = [Weekday.monday.rawValue]

        viewModel.applyPreset(preset)

        XCTAssertEqual(viewModel.title, preset.title)
        XCTAssertEqual(viewModel.iconName, preset.iconName)
        XCTAssertEqual(viewModel.period, .week)
        XCTAssertEqual(viewModel.targetCount, 3)
        XCTAssertFalse(viewModel.notifyAtScheduledTime)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allWeekdayValues))
    }

    func testCustomSelectionClearsValuesFromPreviouslySelectedPreset() {
        let viewModel = RoutineEditViewModel(routine: nil)
        viewModel.applyPreset(RoutinePreset.all[0])
        viewModel.period = .month
        viewModel.targetCount = 8
        viewModel.notifyAtScheduledTime = true

        viewModel.prepareCustomRoutine()

        XCTAssertEqual(viewModel.title, "")
        XCTAssertNil(viewModel.iconName)
        XCTAssertEqual(viewModel.period, .day)
        XCTAssertEqual(viewModel.targetCount, 1)
        XCTAssertFalse(viewModel.notifyAtScheduledTime)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allWeekdayValues))
    }

    func testApplyingPresetDoesNotOverwriteExistingRoutine() {
        let routine = Routine(title: "既存の約束", iconName: "star")
        let viewModel = RoutineEditViewModel(routine: routine)

        viewModel.applyPreset(RoutinePreset.all[0])

        XCTAssertEqual(viewModel.title, "既存の約束")
        XCTAssertEqual(viewModel.iconName, "star")
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
