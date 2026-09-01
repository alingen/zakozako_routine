import Foundation
import SwiftData
import Observation

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
    /// 前日分の「まもれた/まもれなかった」がまだ未記録なら、その確認対象。
    private(set) var pendingCheckInBehavior: BlockedBehavior?
    /// 解放済みで未完了のイベント(あれば「話したいことがあるみたい」を出す)。
    private(set) var presentableEvent: EventDefinition?
    /// キャラクター名(「〇〇が話したいことがあるみたい」の表示に使う)。
    private(set) var characterName = "小悪魔コーチ"
    var newBlockedBehaviorTitle: String = ""
    var newBlockedBehaviorReason: String = ""
    var newBlockedBehaviorAlternativeAction: String = ""

    /// クイック完了直後に、完了体験(RoutineCompletionPresentation)へ渡す表示データが入る。
    /// View 側はこれが非nilになったら完了 Presentation を出す。閉じる時は `clearCompletion()`。
    private(set) var completionContext: RoutineCompletionContext?

    /// ホーム画面上部に出す、キャラクターからの一言。
    private(set) var homeComment: String = ""
    /// キャラクターの一言を生成している間 true(入力中インジケーターの表示に使う)。
    private(set) var isLoadingHomeComment = false

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

        currentBehavior = dependencies.blockedBehaviorRepository.fetchActive()
        masteredBehaviors = dependencies.blockedBehaviorRepository.fetchMastered()
        pendingCheckInBehavior = dependencies.blockedBehaviorRepository.pendingCheckIn()
        dependencies.eventUnlockService.refreshUnlocks()
        presentableEvent = dependencies.eventUnlockService.nextPresentableEvent()
        rescheduleNotifications()
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

    /// 【レガシー互換】Siri ショートカット経由で「朝/夜ルーティンを開始」された時に、
    /// 対応する既存ルーティンを返す。無ければ nil(呼び出し側で今日のルーティン先頭にフォールバック)。
    func routineForLegacyType(_ type: RoutineType) -> Routine? {
        dependencies?.routineRepository.fetchAll().first { $0.isActive && $0.type == type }
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
            counterMessage: ""
        )
        newBlockedBehaviorTitle = ""
        newBlockedBehaviorReason = ""
        newBlockedBehaviorAlternativeAction = ""
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

    /// 検出ワード・理由・検出時間帯を更新する(詳細編集シート用)。
    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        reason: String,
        alternativeAction: String,
        triggerText: String,
        useTimeWindow: Bool,
        startTime: Date,
        endTime: Date
    ) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            reason: reason,
            alternativeAction: alternativeAction,
            triggerText: triggerText,
            activeStartMinute: useTimeWindow ? BlockedBehavior.minutes(from: startTime) : nil,
            activeEndMinute: useTimeWindow ? BlockedBehavior.minutes(from: endTime) : nil
        )
        reload()
    }

    /// 前日分の「まもれた/まもれなかった」を記録する。
    /// 「まもれた」場合は信頼度を加算し(ルーティン完了と同じ +1)、累積回数を増やしてイベント解放を再評価する。
    func answerCheckIn(protected: Bool) {
        guard let dependencies, let behavior = pendingCheckInBehavior else { return }
        dependencies.blockedBehaviorRepository.recordCheckIn(behavior, protected: protected)
        if protected {
            dependencies.trustRepository.increment(by: 1)
            AppSettingsStore.blockedBehaviorProtectedCount += 1
            dependencies.eventUnlockService.refreshUnlocks()
        }
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

    /// ホーム画面上部のキャラクターコメントを取得し直す。継続日数・今日のルーティン未着手判定を元に生成する。
    func loadHomeComment() async {
        guard let dependencies else { return }
        isLoadingHomeComment = true
        let response = await dependencies.characterEngine.respond(
            to: .homeGreeting(
                streakDays: currentStreakDays(),
                isMorningRoutinePending: isTodayRoutinePending()
            )
        )
        homeComment = response.text
        isLoadingHomeComment = false
    }

    /// 今日を含めて何日連続でルーティンを完了しているか。記録が無ければ1(今日が初日)を返す。
    private func currentStreakDays(calendar: Calendar = .current, now: Date = .now) -> Int {
        guard let dependencies else { return 1 }
        let completedDays = Set(
            dependencies.sessionRepository.fetchAllSessions()
                .filter { $0.status == .completed }
                .compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )
        var streak = 1
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// 「もう習慣を始めていい時間帯(10時以降)なのに、今日のルーティンがまだ1つも完了していない」かどうか。
    /// (旧 isMorningRoutinePending の一般化。キャラの `.homeGreeting` にそのまま渡す)
    private func isTodayRoutinePending(calendar: Calendar = .current, now: Date = .now) -> Bool {
        guard let dependencies, !todayRoutines.isEmpty else { return false }
        guard calendar.component(.hour, from: now) >= 10 else { return false }
        let sessions = dependencies.sessionRepository.fetchAllSessions()
        let completedTodayIds = Set(
            sessions
                .filter { $0.status == .completed && $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true }
                .map(\.routineId)
        )
        return todayRoutines.contains { !completedTodayIds.contains($0.id) }
    }
}
