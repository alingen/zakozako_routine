import Foundation
import SwiftData
import Observation

/// 「やらないこと」カードに出す、現在の期間の消費状況(Streaks風: 残り回数が減っていく)。
struct PromiseUsage {
    let used: Int
    /// 実効上限(1未満は1)。
    let limit: Int
    /// 残り回数。
    var remaining: Int { max(limit - used, 0) }
    /// 「今日 / 今週 / 今月」
    let periodLabel: String
    /// 左アイコンの塗り具合 0.0〜1.0(残り / 上限)。満タンからスタートし、失敗記録で減る。
    var fraction: Double { limit > 0 ? Double(remaining) / Double(limit) : 0 }
    /// 上限に達した(残り0)= 失敗。
    var failed: Bool { used >= limit }
}

@Observable
@MainActor
final class HomeViewModel {
    /// 今日対象になっている約束の一覧。
    private(set) var todayRoutines: [Routine] = []
    /// Routine.id → 現在の期間の進捗。
    private(set) var routineProgressById: [UUID: RoutineTodayProgress] = [:]
    /// Routine.id → 連続達成期間数（日／週／月）。
    private(set) var routineStreakById: [UUID: Int] = [:]

    var todayCompletedCount: Int {
        todayRoutines.filter { routineProgressById[$0.id]?.isCompletedToday == true }.count
    }
    var todayTotalCount: Int { todayRoutines.count }

    func todayProgress(for routine: Routine) -> RoutineTodayProgress {
        routineProgressById[routine.id]
            ?? RoutineTodayProgress(fraction: 0, done: 0, target: routine.targetCount, isCompletedToday: false)
    }

    func currentRoutineStreak(for routine: Routine) -> Int {
        routineStreakById[routine.id] ?? 0
    }

    /// 現在挑戦中の「やらないこと」(あれば1件)。
    private(set) var currentBehavior: BlockedBehavior?
    /// 14日間守り切って卒業した「やらないこと」。新しい順。
    private(set) var masteredBehaviors: [BlockedBehavior] = []

    /// 「みんなのざこ速報」に出す項目(いまは自分の記録だけ。最大3件)。
    private(set) var zakoBulletinItems: [ZakoBulletinItem] = []

    private(set) var routineOperationErrorMessage: String?
    private(set) var blockedBehaviorOperationErrorMessage: String?
    /// Screen Time の権限取消・監視復元失敗を、カード内の再設定導線に表示する。
    private(set) var screenTimeMonitoringIssueMessage: String?

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        // Device Activity拡張の通知を先に取り込む。順序を逆にすると、昨日の超過を
        // 「守れた日」としてautoEvaluateしてしまう。
        dependencies.screenTimeMonitoringService.consumePendingSignals(
            using: dependencies.blockedBehaviorRepository
        )

        let allRoutines = dependencies.routineRepository.fetchAll()
        todayRoutines = Self.computeTodayRoutines(allRoutines)

        var progressMap: [UUID: RoutineTodayProgress] = [:]
        var streakMap: [UUID: Int] = [:]
        for routine in allRoutines {
            progressMap[routine.id] = routine.todayProgress()
            streakMap[routine.id] = RoutineStreak.currentStreak(routine: routine)
        }
        routineProgressById = progressMap
        routineStreakById = streakMap

        screenTimeMonitoringIssueMessage = nil
        if let behavior = dependencies.blockedBehaviorRepository.fetchActive() {
            if behavior.trackingKind == .screenTime {
                do {
                    // Screen Time の達成日は拡張機能の監視完了通知だけで加算する。
                    try dependencies.screenTimeMonitoringService.ensureMonitoring(for: behavior)
                } catch {
                    screenTimeMonitoringIssueMessage = error.localizedDescription
                }
            } else {
                dependencies.blockedBehaviorRepository.autoEvaluate(behavior)
            }

            if behavior.masteredAt != nil {
                dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
            }
        }
        currentBehavior = dependencies.blockedBehaviorRepository.fetchActive()
        masteredBehaviors = dependencies.blockedBehaviorRepository.fetchMastered()
        zakoBulletinItems = Self.buildBulletin(routines: allRoutines, behavior: currentBehavior)
        rescheduleNotifications()
    }

    /// 「みんなのざこ速報」の項目を、自分の最近の記録から組み立てる(最大3件)。
    static func buildBulletin(
        routines: [Routine],
        behavior: BlockedBehavior?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ZakoBulletinItem] {
        let who = AppSettingsStore.userDisplayName
        var entries: [(date: Date, line: String, kind: ZakoBulletinKind)] = []

        for routine in routines where routine.isComplete(now: now) {
            guard let last = routine.progressEvents.max(),
                  calendar.isDate(last, inSameDayAs: now) else { continue }
            entries.append((last, "\(who)が \(routine.title) を達成しました！", .achievement))
        }

        if let behavior, behavior.usageInCurrentPeriod(now: now) >= behavior.effectiveLimit,
           let lastUse = behavior.usageEvents.max(),
           calendar.isDate(lastUse, inSameDayAs: now) {
            entries.append((lastUse, "\(who)が \(behavior.title) に負けました…", .failure))
        }

        return entries
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map {
                ZakoBulletinItem(
                    id: UUID(),
                    line: $0.line,
                    relativeTime: Self.relativeTime(from: $0.date, now: now),
                    kind: $0.kind
                )
            }
    }

    private static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "たった今"
        case ..<3600: return "\(Int(seconds / 60))分前"
        case ..<86_400: return "\(Int(seconds / 3600))時間前"
        default: return "\(Int(seconds / 86_400))日前"
        }
    }

    // MARK: - やらないこと

    func promiseUsage(for behavior: BlockedBehavior, now: Date = .now) -> PromiseUsage {
        PromiseUsage(
            used: behavior.usageInCurrentPeriod(now: now),
            limit: behavior.effectiveLimit,
            periodLabel: behavior.limitPeriod.currentUnitLabel
        )
    }

    /// 最終確認後に「負けました」1回分を記録する。上限到達後は重複記録しない。
    @discardableResult
    func recordPromiseFailure(_ behavior: BlockedBehavior) -> Bool {
        guard let dependencies else { return false }
        do {
            if behavior.trackingKind == .screenTime {
                let now = Date.now
                _ = try dependencies.blockedBehaviorRepository.recordScreenTimeSignal(
                    ScreenTimeMonitorSignal(
                        behaviorID: behavior.id,
                        appDayStart: AppDay.startOfDay(for: now),
                        occurredAt: now,
                        kind: .thresholdExceeded
                    ),
                    for: behavior,
                    processedAt: now
                )
            } else {
                try dependencies.blockedBehaviorRepository.recordFailure(behavior)
            }
            blockedBehaviorOperationErrorMessage = nil
            reload()
            return true
        } catch {
            blockedBehaviorOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    var canAddBlockedBehavior: Bool {
        dependencies?.blockedBehaviorRepository.canAddNew() ?? false
    }

    func requestScreenTimeAuthorization() async throws {
        guard let dependencies else {
            throw ScreenTimeMonitoringError.authorizationFailed(
                "準備が完了していません。画面を開き直してもう一度お試しください。"
            )
        }
        try await dependencies.screenTimeMonitoringService.requestAuthorizationIfNeeded()
    }

    /// 「やらないことを決める」画面の下書きを保存する。成功時はnil、失敗時は理由を返す。
    func addBlockedBehavior(_ draft: BlockedBehaviorDraft) -> String? {
        guard let dependencies else {
            return "保存先を準備できませんでした。もう一度お試しください。"
        }
        guard canAddBlockedBehavior else {
            return "挑戦中の「やらないこと」は同時に1つまでです。"
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "タイトルを入力してください。" }
        guard let behavior = dependencies.blockedBehaviorRepository.create(
            title: title,
            iconName: draft.iconName,
            limitPeriod: draft.effectiveLimitPeriod,
            limitCount: draft.effectiveLimitCount,
            trackingKind: draft.trackingKind,
            screenTimeLimitMinutes: draft.trackingKind == .screenTime
                ? draft.screenTimeLimitMinutes
                : nil,
            screenTimeSelectionData: draft.screenTimeSelectionData
        ) else { return "保存できませんでした。もう一度お試しください。" }

        if behavior.trackingKind == .screenTime {
            do {
                try dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
            } catch {
                _ = dependencies.blockedBehaviorRepository.delete(behavior)
                return error.localizedDescription
            }
        }

        reload()
        return nil
    }

    /// 編集画面の下書きを保存する。進捗は維持し、Screen Time の設定だけ監視を再構成する。
    func updateBlockedBehavior(
        _ behavior: BlockedBehavior,
        with draft: BlockedBehaviorDraft
    ) -> String? {
        guard let dependencies else {
            return "保存先を準備できませんでした。もう一度お試しください。"
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "タイトルを入力してください。" }

        let previousTitle = behavior.title
        let previousIconName = behavior.iconName
        let previousLimitPeriod = behavior.limitPeriod
        let previousLimitCount = behavior.limitCount
        let previousTrackingKind = behavior.trackingKind
        let previousScreenTimeLimitMinutes = behavior.screenTimeLimitMinutes
        let previousScreenTimeSelectionData = behavior.screenTimeSelectionData

        if previousTrackingKind == .screenTime {
            dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
        }

        let didSave = dependencies.blockedBehaviorRepository.update(
            behavior,
            title: title,
            iconName: draft.iconName,
            limitPeriod: draft.effectiveLimitPeriod,
            limitCount: draft.effectiveLimitCount,
            trackingKind: draft.trackingKind,
            screenTimeLimitMinutes: draft.trackingKind == .screenTime
                ? draft.screenTimeLimitMinutes
                : nil,
            screenTimeSelectionData: draft.trackingKind == .screenTime
                ? draft.screenTimeSelectionData
                : nil
        )

        guard didSave else {
            if previousTrackingKind == .screenTime {
                try? dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
            }
            return "保存できませんでした。もう一度お試しください。"
        }

        if draft.trackingKind == .screenTime {
            do {
                try dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
            } catch {
                dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
                _ = dependencies.blockedBehaviorRepository.update(
                    behavior,
                    title: previousTitle,
                    iconName: previousIconName,
                    limitPeriod: previousLimitPeriod,
                    limitCount: previousLimitCount,
                    trackingKind: previousTrackingKind,
                    screenTimeLimitMinutes: previousScreenTimeLimitMinutes,
                    screenTimeSelectionData: previousScreenTimeSelectionData
                )
                if previousTrackingKind == .screenTime {
                    try? dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
                }
                reload()
                return error.localizedDescription
            }
        }

        blockedBehaviorOperationErrorMessage = nil
        reload()
        return nil
    }

    /// カードの再設定導線からScreen Time権限を取り直し、監視を再開する。
    func repairScreenTimeMonitoring(_ behavior: BlockedBehavior) async {
        guard let dependencies, behavior.trackingKind == .screenTime else { return }
        do {
            try await dependencies.screenTimeMonitoringService.requestAuthorizationIfNeeded()
            try dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
            screenTimeMonitoringIssueMessage = nil
            blockedBehaviorOperationErrorMessage = nil
            reload()
        } catch ScreenTimeMonitoringError.authorizationCanceled {
            blockedBehaviorOperationErrorMessage = nil
        } catch {
            screenTimeMonitoringIssueMessage = error.localizedDescription
            blockedBehaviorOperationErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func deleteBlockedBehavior(_ behavior: BlockedBehavior) -> Bool {
        guard let dependencies else { return false }
        dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
        guard dependencies.blockedBehaviorRepository.delete(behavior) else {
            // 保存側だけ失敗した場合は、挑戦中の監視を可能な限り戻す。
            try? dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
            return false
        }
        dependencies.screenTimeMonitoringService.discardStoredSignals(for: behavior)
        reload()
        return true
    }

    func deleteMasteredBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
        if dependencies.blockedBehaviorRepository.delete(behavior) {
            dependencies.screenTimeMonitoringService.discardStoredSignals(for: behavior)
            reload()
        }
    }

    // MARK: - 約束(Routine)

    func deleteRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        do {
            try dependencies.routineRepository.delete(routine)
            routineOperationErrorMessage = nil
            reload()
        } catch {
            routineOperationErrorMessage = error.localizedDescription
        }
    }

    /// タイマー完了など、約束の実行を1回ぶん記録する。
    @discardableResult
    func advanceRoutine(_ routine: Routine, now: Date = .now) -> Bool {
        // 達成済みの期間には追加ログを積まない。日/週/月の次の期間に入ると再び記録できる。
        guard let dependencies else { return false }
        guard !routine.isComplete(now: now) else { return true }
        do {
            try dependencies.routineRepository.recordProgress(routine, now: now)
            routineOperationErrorMessage = nil
        } catch {
            routineOperationErrorMessage = error.localizedDescription
            return false
        }
        reload()
        return true
    }

    /// 現在期間の達成状態を明示的に切り替える。
    /// Home の通常タップは `advanceRoutine` で1回ずつ記録し、これは主に完了後の報告取り消しに使う。
    @discardableResult
    func setRoutineCompletion(
        _ routine: Routine,
        completed: Bool,
        now: Date = .now
    ) -> Bool {
        guard let dependencies else { return false }
        guard routine.isComplete(now: now) != completed else { return true }

        do {
            try dependencies.routineRepository.setCompletion(
                routine,
                completed: completed,
                now: now
            )
            routineOperationErrorMessage = nil
        } catch {
            routineOperationErrorMessage = error.localizedDescription
            return false
        }

        reload()
        return true
    }

    func clearRoutineOperationError() {
        routineOperationErrorMessage = nil
    }

    func clearBlockedBehaviorOperationError() {
        blockedBehaviorOperationErrorMessage = nil
    }

    /// 中立 App Intent「今日の約束を開く」の遷移先。今日ぶんで未完了の先頭、無ければ先頭。
    func firstPendingTodayRoutine() -> Routine? {
        todayRoutines.first { routineProgressById[$0.id]?.isCompletedToday != true } ?? todayRoutines.first
    }

    // MARK: - helpers

    private func rescheduleNotifications() {
        guard let dependencies else { return }
        let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
        Task {
            await dependencies.notificationScheduler.reschedule(routines: routines)
        }
    }

    /// 今日対象の約束を、開始予定時刻→作成日順で返す。
    static func computeTodayRoutines(
        _ all: [Routine],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Routine] {
        all
            .filter { $0.isActive && $0.isScheduled(on: now, calendar: calendar) }
            .sorted { lhs, rhs in
                switch (lhs.scheduledStartMinute, rhs.scheduledStartMinute) {
                case let (l?, r?):
                    return l != r ? l < r : lhs.createdAt < rhs.createdAt
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.createdAt < rhs.createdAt
                }
            }
    }
}
