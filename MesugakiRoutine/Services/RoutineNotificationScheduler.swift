import Foundation
import UserNotifications

/// ルーティンの「サボり通知」をローカル通知でスケジュールする。
/// 通知の中身はサーバーを介さずデバイス内で完結させるため、リマインド時刻には
/// ルーティンが今日まだ完了していない場合のみ通知が届くよう、状態が変わるたびに再スケジュールする。
@MainActor
final class RoutineNotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    /// 渡された約束ぶんの通知を再計算してスケジュールし直す。
    /// 通知の有効/無効・何分後に通知するかは全体共通(AppSettingsStore)。
    /// 今日(その期間)すでに達成している約束や、開始予定時刻が未設定の約束は通知を出さない。
    func reschedule(
        routines: [Routine],
        calendar: Calendar = .current,
        now: Date = .now,
        notBefore: Date? = nil
    ) async {
        let delayMinutes = AppSettingsStore.notificationDelayMinutes

        for routine in routines {
            let identifier = Self.identifier(for: routine)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])

            guard AppSettingsStore.notificationsEnabled,
                  let startMinute = routine.scheduledStartMinute else { continue }

            // 今日が達成済み・時刻経過後でも、次の未達成期間の通知を残す。
            // これによりオンボーディングで予約した翌日通知も、通常の再計算で消えない。
            let fireDate = Self.nextEligibleFireDate(
                for: routine,
                startMinute: startMinute,
                delayMinutes: delayMinutes,
                notBefore: resolvedNotBefore(
                    for: routine.id,
                    requestedNotBefore: notBefore,
                    now: now
                ),
                calendar: calendar,
                now: now
            )
            guard let fireDate else { continue }

            let hasSomeProgress = routine.progressCount(now: fireDate, calendar: calendar) > 0
            let content = UNMutableNotificationContent()
            content.title = "ざこルーティン"
            content.body = hasSomeProgress
                ? "ちょっと〜、\(routine.title)とちゅうで放置とか一番ざこいパターンだよ〜？さっさと終わらせなよ〜♡"
                : "うわっ、まだ\(routine.title)やってすらいないの？ざっこ〜♡サボり確定じゃん〜"
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// オンボーディング通知を取り消す時に、同じRoutineの予約だけを確実に削除する。
    func cancelNotification(for routineID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(for: routineID)]
        )
    }

    /// 明日開始の初回通知は、通常のforeground/reload由来の再計算でも前倒ししない。
    func resolvedNotBefore(
        for routineID: UUID,
        requestedNotBefore: Date?,
        now: Date
    ) -> Date {
        let persisted = OnboardingStateStore.persistedNotificationNotBefore(
            for: routineID,
            defaults: defaults
        )
        return [now, requestedNotBefore, persisted]
            .compactMap { $0 }
            .max() ?? now
    }

    /// 指定した「時刻(分)」の次回発火日時を返す。今日その時刻がまだ来ていなければ今日、過ぎていれば翌日。
    /// `notBefore` 以降で、対象曜日かつ未達成期間に入る最初の通知日時を探す。
    /// オンボーディング完了時は今日の達成状態に関係なく「明日」から探すために使う。
    static func nextEligibleFireDate(
        for routine: Routine,
        startMinute: Int,
        delayMinutes: Int,
        notBefore: Date,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        let firstDay = calendar.startOfDay(for: notBefore)

        // 日次の曜日指定に加え、週・月の次期間も十分に探索できる範囲。
        for dayOffset in 0...370 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay),
                  let start = calendar.date(
                    bySettingHour: startMinute / 60,
                    minute: startMinute % 60,
                    second: 0,
                    of: day
                  ),
                  routine.isScheduled(on: start, calendar: calendar),
                  let candidate = calendar.date(
                    byAdding: .minute,
                    value: delayMinutes,
                    to: start
                  ),
                  candidate >= notBefore,
                  candidate > now,
                  !routine.isComplete(now: candidate, calendar: calendar) else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func identifier(for routine: Routine) -> String {
        identifier(for: routine.id)
    }

    private static func identifier(for routineID: UUID) -> String {
        "routine-reminder-\(routineID.uuidString)"
    }
}
