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

    private let news: ZakoNewsStore

    init(news: ZakoNewsStore? = nil) { self.news = news ?? .shared }

    private(set) var routineOperationErrorMessage: String?
    private(set) var blockedBehaviorOperationErrorMessage: String?
    /// Screen Time の権限取消・監視復元失敗を、カード内の再設定導線に表示する。
    private(set) var screenTimeMonitoringIssueMessage: String?

    /// Home上部で莉央が話している一言。
    private(set) var rioComment: InteractionComment?
    private(set) var prohibitionReactionText: String?
    /// `rioComment` を選んだときの状態。状態が変わったら選び直す。
    private var rioCommentMood: RioHomeMood?

    /// 今日の記録から決まる莉央の状態。負けた日は達成より優先してからかう。
    var rioMood: RioHomeMood {
        if let currentBehavior, promiseUsage(for: currentBehavior).failed {
            return .defeated
        }
        if todayTotalCount > 0, todayCompletedCount == todayTotalCount {
            return .allDone
        }
        return todayCompletedCount > 0 ? .inProgress : .notStarted
    }

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
        // 再読み込みのたびに入れ替えるとせわしないので、状態が変わったときだけ選び直す。
        if rioComment == nil || rioCommentMood != rioMood {
            selectNextRioComment()
        }
        rescheduleNotifications()
    }

    // MARK: - 莉央

    /// 今の状態に合う一言へ切り替える。状態専用の行がシートに無ければ、交流タブと同じ一言を使う。
    func selectNextRioComment() {
        let mood = rioMood
        rioComment = interactionComment(touchArea: mood.commentTouchArea, excluding: rioComment?.id)
            ?? interactionComment(touchArea: "character", excluding: rioComment?.id)
        rioCommentMood = mood
    }

    /// 達成時の反応。シートに専用の行があればそれを、無ければ既定の一言を使う。
    func makeRioReaction(_ kind: RioReactionKind) -> RioReaction {
        let text = interactionComment(touchArea: kind.commentTouchArea, excluding: nil)?.text
            ?? kind.fallbackMessages.randomElement()
            ?? ""
        return RioReaction(kind: kind, text: text)
    }

    private func interactionComment(touchArea: String, excluding excludedID: String?) -> InteractionComment? {
        guard let dependencies, let content = dependencies.storyContentRepository else { return nil }
        let profileValues = (try? dependencies.storyStateRepository.profileValues()) ?? [:]
        return InteractionCommentSelector.select(
            from: content.interactions,
            touchArea: touchArea,
            profileValues: profileValues,
            excluding: excludedID
        )
    }

    // MARK: - やらないこと

    @discardableResult
    func recordPromiseUrge(_ behavior: BlockedBehavior) -> Bool {
        guard let dependencies else { return false }
        prohibitionReactionText = nil
        do {
            let now = Date.now
            let event = try dependencies.blockedBehaviorRepository.recordUrge(behavior, now: now)
            selectProhibitionReaction(eventID: event.id, now: now)
            blockedBehaviorOperationErrorMessage = nil
            return true
        } catch {
            blockedBehaviorOperationErrorMessage = error.localizedDescription
            return false
        }
    }

    private func selectProhibitionReaction(eventID: UUID, now: Date) {
        guard let dependencies, let content = dependencies.storyContentRepository,
              let context = try? dependencies.reactionContextProvider.current(now: now) else { return }
        prohibitionReactionText = dependencies.interactionReactionService.select(
            conditions: content.reactionConditions, lines: content.reactionLines,
            interactions: content.interactions, context: context, trigger: .action(eventID), now: now
        )?.displayText
    }

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
        prohibitionReactionText = nil
        do {
            let now = Date.now
            let didRecord: Bool
            if behavior.trackingKind == .screenTime {
                didRecord = try dependencies.blockedBehaviorRepository.recordScreenTimeSignal(
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
                didRecord = try dependencies.blockedBehaviorRepository.recordFailure(behavior, now: now) == .recorded
            }
            if didRecord {
                news.enqueue(.failure(behavior, now: now))
                if behavior.trackingKind == .manual,
                   let event = try dependencies.userActionEventRepository.fetchAll().last(where: {
                       $0.eventType == .prohibitionFailed && $0.targetID == behavior.id && $0.occurredAt == now
                   }) {
                    selectProhibitionReaction(eventID: event.id, now: now)
                }
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
            screenTimeSelectionData: draft.screenTimeSelectionData,
            shareToZakoNews: draft.shareToZakoNews
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
        let previousSharing = behavior.shareToZakoNews
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
                : nil,
            shareToZakoNews: draft.shareToZakoNews
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
                    screenTimeSelectionData: previousScreenTimeSelectionData,
                    shareToZakoNews: previousSharing
                )
                if previousTrackingKind == .screenTime {
                    try? dependencies.screenTimeMonitoringService.startMonitoring(for: behavior)
                }
                reload()
                return error.localizedDescription
            }
        }

        if !draft.shareToZakoNews { news.cancelPending(for: behavior.id) }
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
        news.cancelPending(for: behavior.id)
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
            let routineID = routine.id
            try dependencies.routineRepository.delete(routine)
            news.cancelPending(for: routineID)
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
            news.enqueue(.achievement(routine, now: now))
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
            if completed { news.enqueue(.achievement(routine, now: now)) }
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
