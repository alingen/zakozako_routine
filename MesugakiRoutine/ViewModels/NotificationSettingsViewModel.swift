import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class NotificationSettingsViewModel {
    private(set) var morningRoutine: Routine?
    private(set) var nightRoutine: Routine?

    var morningReminderEnabled: Bool = false
    var morningReminderTime: Date = Routine.date(fromMinutes: 8 * 60)
    var nightReminderEnabled: Bool = false
    var nightReminderTime: Date = Routine.date(fromMinutes: 22 * 60)

    /// システム側で通知が許可されていないと思われる場合に true(未許可バナーの表示用)。
    private(set) var isSystemAuthorizationDenied = false

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        morningRoutine = dependencies.routineRepository.fetch(type: .morning).first
        nightRoutine = dependencies.routineRepository.fetch(type: .night).first

        if let morningRoutine {
            morningReminderEnabled = morningRoutine.reminderEnabled
            if let minute = morningRoutine.reminderMinuteOfDay {
                morningReminderTime = Routine.date(fromMinutes: minute)
            }
        }
        if let nightRoutine {
            nightReminderEnabled = nightRoutine.reminderEnabled
            if let minute = nightRoutine.reminderMinuteOfDay {
                nightReminderTime = Routine.date(fromMinutes: minute)
            }
        }

        Task {
            let authorized = await dependencies.notificationScheduler.isAuthorized
            isSystemAuthorizationDenied = !authorized
        }
    }

    func setMorningReminder(enabled: Bool) {
        morningReminderEnabled = enabled
        if enabled { requestAuthorizationIfNeeded() }
        persistMorning()
    }

    func setMorningReminderTime(_ time: Date) {
        morningReminderTime = time
        persistMorning()
    }

    func setNightReminder(enabled: Bool) {
        nightReminderEnabled = enabled
        if enabled { requestAuthorizationIfNeeded() }
        persistNight()
    }

    func setNightReminderTime(_ time: Date) {
        nightReminderTime = time
        persistNight()
    }

    private func persistMorning() {
        guard let dependencies, let morningRoutine else { return }
        dependencies.routineRepository.updateReminder(
            morningRoutine,
            enabled: morningReminderEnabled,
            minuteOfDay: Routine.minutes(from: morningReminderTime)
        )
        rescheduleAll()
    }

    private func persistNight() {
        guard let dependencies, let nightRoutine else { return }
        dependencies.routineRepository.updateReminder(
            nightRoutine,
            enabled: nightReminderEnabled,
            minuteOfDay: Routine.minutes(from: nightReminderTime)
        )
        rescheduleAll()
    }

    private func rescheduleAll() {
        guard let dependencies else { return }
        let routines = [morningRoutine, nightRoutine].compactMap { $0 }
        Task {
            await dependencies.notificationScheduler.reschedule(
                routines: routines,
                sessionRepository: dependencies.sessionRepository
            )
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard let dependencies else { return }
        Task {
            await dependencies.notificationScheduler.requestAuthorizationIfNeeded()
            let authorized = await dependencies.notificationScheduler.isAuthorized
            isSystemAuthorizationDenied = !authorized
        }
    }
}
