import Foundation
import SwiftData
import Observation

/// 「今日の約束」カードに出す、現在の期間の消費状況。
struct PromiseUsage {
    let used: Int
    let limit: Int
    /// 「今日 / 今週 / 今月」
    let periodLabel: String
    /// 円グラフ用 0.0〜1.0(消費 / 上限)。
    let fraction: Double
    /// 上限を超えているか。
    let exceeded: Bool
}

@Observable
@MainActor
final class HomeViewModel {
    /// 今日実行対象になっているルーティンの一覧。
    /// isActive かつ「今日の曜日が対象曜日に含まれる(未指定なら毎日扱い)」もの。
    /// 並び順: 開始予定時刻あり(時刻昇順) → 時刻なし → 同条件は作成日順。
    private(set) var todayRoutines: [Routine] = []

    /// Routine.id → 今日の進捗(0.0〜1.0 と内訳)。`reload()` で全 Routine ぶん再計算する。
    private(set) var routineProgressById: [UUID: RoutineTodayProgress] = [:]
    /// Routine.id → そのルーティンの連続達成回数(履歴から計算、保存値ではない)。
    private(set) var routineStreakById: [UUID: Int] = [:]

    /// 今日完了しているルーティン数 / 今日対象のルーティン総数。ヘッダーの「2 / 4」に使う。
    var todayCompletedCount: Int {
        todayRoutines.filter { routineProgressById[$0.id]?.isCompletedToday == true }.count
    }
    var todayTotalCount: Int { todayRoutines.count }

    /// UI に依存しない取得口(Step 4 の行 View から使う)。
    func todayProgress(for routine: Routine) -> RoutineTodayProgress {
        routineProgressById[routine.id]
            ?? RoutineTodayProgress(fraction: 0, completedSteps: 0, totalSteps: 0, isCompletedToday: false)
    }

    func currentRoutineStreak(for routine: Routine) -> Int {
        routineStreakById[routine.id] ?? 0
    }

    /// 現在挑戦中の「やらないこと」(あれば1件)。
    private(set) var currentBehavior: BlockedBehavior?
    /// 14日間守り切って卒業した「やらないこと」。新しい順。
    private(set) var masteredBehaviors: [BlockedBehavior] = []
    /// 解放済みで未完了のイベント(あれば「話したいことがあるみたい」を出す)。
    private(set) var presentableEvent: EventDefinition?
    /// キャラクター名(「〇〇が話したいことがあるみたい」の表示に使う)。
    private(set) var characterName = "小悪魔コーチ"
    var newBlockedBehaviorTitle: String = ""
    var newBlockedBehaviorReason: String = ""
    var newBlockedBehaviorAlternativeAction: String = ""
    var newBlockedBehaviorLimitPeriod: BlockedBehaviorLimitPeriod = .day
    var newBlockedBehaviorLimitCount: Int = 0

    /// 「みんなのざこ速報」に出す項目(いまは自分の記録だけ。最大3件)。
    private(set) var zakoBulletinItems: [ZakoBulletinItem] = []

    /// クイック完了直後に、完了体験(RoutineCompletionPresentation)へ渡す表示データが入る。
    /// View 側はこれが非nilになったら完了 Presentation を出す。閉じる時は `clearCompletion()`。
    private(set) var completionContext: RoutineCompletionContext?

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        characterName = dependencies?.characterEngine.activePreset.name ?? characterName
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        let allRoutines = dependencies.routineRepository.fetchAll()
        todayRoutines = Self.computeTodayRoutines(allRoutines)

        let sessions = dependencies.sessionRepository.fetchAllSessions()
        var progressMap: [UUID: RoutineTodayProgress] = [:]
        var streakMap: [UUID: Int] = [:]
        for routine in allRoutines {
            progressMap[routine.id] = RoutineProgressCalculator.todayProgress(routine: routine, sessions: sessions)
            streakMap[routine.id] = RoutineStreakCalculator.currentStreak(routine: routine, sessions: sessions)
        }
        routineProgressById = progressMap
        routineStreakById = streakMap

        evaluatePromiseIfNeeded()
        currentBehavior = dependencies.blockedBehaviorRepository.fetchActive()
        masteredBehaviors = dependencies.blockedBehaviorRepository.fetchMastered()
        dependencies.eventUnlockService.refreshUnlocks()
        presentableEvent = dependencies.eventUnlockService.nextPresentableEvent()
        zakoBulletinItems = Self.buildBulletin(routines: allRoutines, sessions: sessions, behavior: currentBehavior)
        rescheduleNotifications()
    }

    /// 「みんなのざこ速報」の項目を、自分の最近の記録から組み立てる(最大3件)。
    /// - ルーティン完了 → 「〇〇が △△ を達成しました！」
    /// - 今日、約束の回数上限を超過 → 「〇〇が △△ に負けました…」
    static func buildBulletin(
        routines: [Routine],
        sessions: [RoutineSession],
        behavior: BlockedBehavior?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ZakoBulletinItem] {
        let who = AppSettingsStore.userNickname
        let titleById = Dictionary(routines.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var entries: [(date: Date, line: String)] = []

        for session in sessions where session.status == .completed {
            guard let completedAt = session.completedAt,
                  let title = titleById[session.routineId] else { continue }
            entries.append((completedAt, "\(who)が \(title) を達成しました！"))
        }

        if let behavior, behavior.usageInCurrentPeriod(now: now) > behavior.limitCount,
           let lastUse = behavior.usageEvents.max(),
           calendar.isDate(lastUse, inSameDayAs: now) {
            entries.append((lastUse, "\(who)が \(behavior.title) に負けました…"))
        }

        return entries
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { ZakoBulletinItem(id: UUID(), line: $0.line, relativeTime: Self.relativeTime(from: $0.date, now: now)) }
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

    /// 現在挑戦中の約束について、前日までの達成/失敗を自動判定する(手動チェックインの置き換え)。
    /// 新たに「達成」と判定された日数ぶん、信頼度と「まもれた累積回数」を加算する。
    private func evaluatePromiseIfNeeded() {
        guard let dependencies, let behavior = dependencies.blockedBehaviorRepository.fetchActive() else { return }
        let keptDays = dependencies.blockedBehaviorRepository.autoEvaluate(behavior)
        guard keptDays > 0 else { return }
        dependencies.trustRepository.increment(by: keptDays)
        AppSettingsStore.blockedBehaviorProtectedCount += keptDays
    }

    /// 約束カードの消費状況(期間内の消費回数 / 上限 と、円グラフ用の割合)。
    func promiseUsage(for behavior: BlockedBehavior, now: Date = .now) -> PromiseUsage {
        let used = behavior.usageInCurrentPeriod(now: now)
        let limit = behavior.limitCount
        let fraction: Double
        if limit > 0 {
            fraction = min(Double(used) / Double(limit), 1)
        } else {
            fraction = used > 0 ? 1 : 0
        }
        return PromiseUsage(
            used: used,
            limit: limit,
            periodLabel: behavior.limitPeriod.currentUnitLabel,
            fraction: fraction,
            exceeded: used > limit
        )
    }

    /// 約束カードのタップで「1回消費」する。
    func consumePromise(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.consume(behavior)
        reload()
    }

    /// サボり通知を、現在のルーティン状態(今日完了済みかどうか)にあわせて再計算する。
    private func rescheduleNotifications() {
        guard let dependencies else { return }
        let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
        Task {
            await dependencies.notificationScheduler.reschedule(
                routines: routines,
                sessionRepository: dependencies.sessionRepository
            )
        }
    }

    /// 今日実行対象のルーティンを、指定の並び順で返す。
    static func computeTodayRoutines(
        _ all: [Routine],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Routine] {
        let todayWeekday = calendar.component(.weekday, from: now)
        return all
            .filter { routine in
                guard routine.isActive else { return false }
                return routine.activeWeekdayValues.isEmpty
                    || routine.activeWeekdayValues.contains(todayWeekday)
            }
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

    /// 現在挑戦中の項目が無い(未着手 or 卒業済み)場合のみ、新しい「やらないこと」を追加できる。
    var canAddBlockedBehavior: Bool {
        dependencies?.blockedBehaviorRepository.canAddNew() ?? false
    }

    func addBlockedBehavior() {
        guard let dependencies, canAddBlockedBehavior else { return }
        let title = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let reason = newBlockedBehaviorReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternativeAction = newBlockedBehaviorAlternativeAction.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.blockedBehaviorRepository.create(
            title: title,
            reason: reason,
            alternativeAction: alternativeAction,
            triggerText: title,
            counterMessage: "",
            limitPeriod: newBlockedBehaviorLimitPeriod,
            limitCount: max(0, newBlockedBehaviorLimitCount)
        )
        newBlockedBehaviorTitle = ""
        newBlockedBehaviorReason = ""
        newBlockedBehaviorAlternativeAction = ""
        newBlockedBehaviorLimitPeriod = .day
        newBlockedBehaviorLimitCount = 0
        reload()
    }

    func deleteMasteredBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.delete(behavior)
        reload()
    }

    func deleteRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        dependencies.routineRepository.delete(routine)
        reload()
    }

    /// Home から「行/円タップだけ」で完了できる習慣か。0〜1ステップのものだけ。
    /// 複数ステップの習慣は従来どおり RoutineSessionView へ遷移させる。
    func isQuickCompletable(_ routine: Routine) -> Bool {
        routine.orderedSteps.count <= 1
    }

    /// 0〜1ステップの習慣を Home から即完了する。
    /// セッション作成 → completed → completedRoutine イベント → 共通の完了後処理(Trust +1 等)。
    /// 今日すでに完了済みなら何もしない(共通サービス側でも同日重複は弾かれる)。
    func quickComplete(_ routine: Routine) {
        guard let dependencies else { return }
        guard isQuickCompletable(routine) else { return }
        guard !todayProgress(for: routine).isCompletedToday else { return }
        let result = dependencies.routineCompletionService.completeQuickly(routine: routine)
        reload()
        completionContext = RoutineCompletionContext(
            routineTitle: routine.title,
            currentStreak: routineStreakById[routine.id] ?? 0,
            trustAwarded: result.trustAwarded,
            // TODO(Step 6): 「今日のルーティンが全部完了した時だけ」今日の会話を提案する。
            offersTodayConversation: false
        )
    }

    /// 完了体験を閉じる。
    func clearCompletion() {
        completionContext = nil
    }

    /// 検出ワード・理由・検出時間帯・回数制限を更新する(詳細編集シート用)。
    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        reason: String,
        alternativeAction: String,
        triggerText: String,
        useTimeWindow: Bool,
        startTime: Date,
        endTime: Date,
        limitPeriod: BlockedBehaviorLimitPeriod,
        limitCount: Int
    ) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            reason: reason,
            alternativeAction: alternativeAction,
            triggerText: triggerText,
            activeStartMinute: useTimeWindow ? BlockedBehavior.minutes(from: startTime) : nil,
            activeEndMinute: useTimeWindow ? BlockedBehavior.minutes(from: endTime) : nil,
            limitPeriod: limitPeriod,
            limitCount: max(0, limitCount)
        )
        reload()
    }

    /// 「負けそう」ボタンから、現在挑戦中の「やらないこと」に対するキャラクターの声かけを取得する。
    /// ルーティンセッション外からの呼び出しのため、RoutineEngineには一切触れずCharacterEngineだけを使う。
    func confrontTemptation() async -> String {
        guard let dependencies else { return "" }
        let response = await dependencies.characterEngine.respond(
            to: .blockedBehaviorDetected(
                behaviorTitle: currentBehavior?.title ?? "",
                counterMessage: currentBehavior?.counterMessage ?? "",
                reason: currentBehavior?.reason ?? "",
                alternativeAction: currentBehavior?.alternativeAction ?? ""
            )
        )
        return response.text
    }

    /// 中断中(完了していない)のセッションがあれば、その現在のステップ名を返す。無ければ nil。
    /// ホーム画面で「〇〇まで進行中」の表示・開始/再開ボタンの出し分けに使う。
    func inProgressStepTitle(for routine: Routine?) -> String? {
        guard let dependencies, let routine else { return nil }
        guard let session = dependencies.sessionRepository.fetchActiveSession(routineId: routine.id) else { return nil }
        guard let stepId = session.currentStepId else { return nil }
        return routine.orderedSteps.first { $0.id == stepId }?.title
    }

    /// 中立 App Intent「今日のルーティンを開く」の遷移先。今日ぶんで未完了の先頭、無ければ先頭のルーティン。
    func firstPendingTodayRoutine() -> Routine? {
        todayRoutines.first { routineProgressById[$0.id]?.isCompletedToday != true } ?? todayRoutines.first
    }
}
