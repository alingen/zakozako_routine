import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class NotificationSettingsViewModel {
    /// サボり通知(全ルーティン共通)を有効にするか。
    var notificationsEnabled: Bool = AppSettingsStore.notificationsEnabled
    /// 各ルーティンの開始予定時刻から何分後に通知するか(全ルーティン共通)。
    var delayMinutes: Int = AppSettingsStore.notificationDelayMinutes

    /// 開始予定時刻が設定されている、有効なルーティン一覧(設定状況の確認表示用)。
    private(set) var routines: [Routine] = []

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
        routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }

        Task {
            let authorized = await dependencies.notificationScheduler.isAuthorized
            isSystemAuthorizationDenied = !authorized
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        AppSettingsStore.notificationsEnabled = enabled
        if enabled { requestAuthorizationIfNeeded() }
        rescheduleAll()
    }

    func setDelayMinutes(_ minutes: Int) {
        delayMinutes = minutes
        AppSettingsStore.notificationDelayMinutes = minutes
        rescheduleAll()
    }

    private func rescheduleAll() {
        guard let dependencies else { return }
        Task {
            await dependencies.notificationScheduler.reschedule(routines: routines)
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
