import XCTest
@testable import MesugakiRoutine

@MainActor
final class RoutineNotificationSchedulerTests: XCTestCase {
    func testOnboardingReminderStartsTomorrowEvenWhenPromiseWasCompletedToday() throws {
        let now = try date(2026, 9, 20, 12, 0)
        let completedAt = try date(2026, 9, 20, 10, 0)
        let tomorrow = try date(2026, 9, 21, 0, 0)
        let routine = Routine(
            title: "本を1ページ読む",
            createdAt: try date(2026, 9, 20, 4, 0),
            updatedAt: completedAt,
            scheduledStartMinute: 20 * 60,
            progressEvents: [completedAt]
        )

        let fireDate = RoutineNotificationScheduler.nextEligibleFireDate(
            for: routine,
            startMinute: 20 * 60,
            delayMinutes: 30,
            notBefore: tomorrow,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fireDate, try date(2026, 9, 21, 20, 30))
    }

    func testRegularRescheduleKeepsTheNextPeriodReminderAfterTodayIsComplete() throws {
        let now = try date(2026, 9, 20, 12, 0)
        let completedAt = try date(2026, 9, 20, 10, 0)
        let routine = Routine(
            title: "本を1ページ読む",
            createdAt: try date(2026, 9, 20, 4, 0),
            updatedAt: completedAt,
            scheduledStartMinute: 20 * 60,
            progressEvents: [completedAt]
        )

        let fireDate = RoutineNotificationScheduler.nextEligibleFireDate(
            for: routine,
            startMinute: 20 * 60,
            delayMinutes: 30,
            notBefore: now,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fireDate, try date(2026, 9, 21, 20, 30))
    }

    func testOnboardingReminderSkipsInactiveWeekdays() throws {
        let now = try date(2026, 9, 20, 12, 0) // Sunday
        let tomorrow = try date(2026, 9, 21, 0, 0) // Monday
        let routine = Routine(
            title: "本を読む",
            createdAt: try date(2026, 9, 20, 4, 0),
            scheduledStartMinute: 8 * 60,
            activeWeekdayValues: [Weekday.tuesday.rawValue]
        )

        let fireDate = RoutineNotificationScheduler.nextEligibleFireDate(
            for: routine,
            startMinute: 8 * 60,
            delayMinutes: 30,
            notBefore: tomorrow,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fireDate, try date(2026, 9, 22, 8, 30))
    }

    func testRegularRescheduleUsesPersistedOnboardingLowerBound() throws {
        let suiteName = "RoutineNotificationSchedulerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let routineID = UUID()
        let store = OnboardingStateStore(defaults: defaults)
        store.beginInAppTutorial(createdRoutineID: routineID)
        store.completePrologue()
        store.completePrologueMessage()
        store.completeFirstReport(with: .deferred)
        store.completeFirstReport(with: .completed)
        store.completeConversationPrompt(with: .later)
        store.completeStoryUnlockPresentation()
        let tomorrow = try date(2026, 9, 21, 0, 0)
        store.beginNotificationSetup(
            routineID: routineID,
            reminderMinuteOfDay: 20 * 60,
            notBefore: tomorrow,
            originalScheduledStartMinute: nil,
            originalNotificationsEnabled: false
        )

        let scheduler = RoutineNotificationScheduler(defaults: defaults)
        let resolved = scheduler.resolvedNotBefore(
            for: routineID,
            requestedNotBefore: nil,
            now: try date(2026, 9, 20, 12, 0)
        )

        XCTAssertEqual(resolved, tomorrow)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return value
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
