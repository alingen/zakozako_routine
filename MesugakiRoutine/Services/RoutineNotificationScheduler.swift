import Foundation
import UserNotifications

/// ルーティンの「サボり通知」をローカル通知でスケジュールする。
/// 通知の中身はサーバーを介さずデバイス内で完結させるため、リマインド時刻には
/// ルーティンが今日まだ完了していない場合のみ通知が届くよう、状態が変わるたびに再スケジュールする。
@MainActor
final class RoutineNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    /// 通知の許可状態を確認し、未確認ならリクエストする。既に拒否されている場合は何もしない。
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    /// 渡されたルーティンぶんの通知を再計算してスケジュールし直す。
    /// 通知の有効/無効・何分後に通知するかは全ルーティン共通(AppSettingsStore)。
    /// 今日既に完了しているルーティンや、開始予定時刻が未設定のルーティンは通知を出さない(既存の予約があれば取り消す)。
    func reschedule(
        routines: [Routine],
        sessionRepository: RoutineSessionRepository,
        calendar: Calendar = .current,
        now: Date = .now
    ) async {
        let sessions = sessionRepository.fetchAllSessions()
        let delayMinutes = AppSettingsStore.notificationDelayMinutes

        for routine in routines {
            let identifier = Self.identifier(for: routine)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])

            guard AppSettingsStore.notificationsEnabled,
                  let startMinute = routine.scheduledStartMinute
            else { continue }

            let todaySessions = sessions.filter { $0.routineId == routine.id && calendar.isDate($0.startedAt, inSameDayAs: now) }
            let completedToday = todaySessions.contains { $0.status == .completed }
            guard !completedToday else { continue }

            let minuteOfDay = (startMinute + delayMinutes) % (24 * 60)
            guard let fireDate = nextFireDate(minuteOfDay: minuteOfDay, calendar: calendar, now: now) else { continue }

            let startedButNotFinished = todaySessions.contains { $0.status == .active }
            let content = UNMutableNotificationContent()
            content.title = "小悪魔コーチ"
            content.body = startedButNotFinished
                ? "ちょっと〜、\(routine.title)とちゅうで放置とか一番ざこいパターンだよ〜？さっさと終わらせなよ〜♡"
                : "うわっ、まだ\(routine.title)始めてすらいないの？ざっこ〜♡サボり確定じゃん〜"
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// 指定した「時刻(分)」の次回発火日時を返す。今日その時刻がまだ来ていなければ今日、過ぎていれば翌日。
    private func nextFireDate(minuteOfDay: Int, calendar: Calendar, now: Date) -> Date? {
        guard let todayTarget = calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: now
        ) else { return nil }

        if todayTarget > now {
            return todayTarget
        }
        return calendar.date(byAdding: .day, value: 1, to: todayTarget)
    }

    private static func identifier(for routine: Routine) -> String {
        "routine-reminder-\(routine.id.uuidString)"
    }
}
