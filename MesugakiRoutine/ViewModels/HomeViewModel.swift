import Foundation
import SwiftData
import Observation

/// 「今日の約束」カードに出す、現在の期間の消費状況(Streaks風: 残り回数が減っていく)。
struct PromiseUsage {
    let used: Int
    /// 実効上限(1未満は1)。
    let limit: Int
    /// 残り回数。
    var remaining: Int { max(limit - used, 0) }
    /// 「今日 / 今週 / 今月」
    let periodLabel: String
    /// チェックボックスの塗り具合 0.0〜1.0(残り / 上限)。満タンからスタートし、タップで減る。
    var fraction: Double { limit > 0 ? Double(remaining) / Double(limit) : 0 }
    /// 上限に達した(残り0)= 失敗。チェックボックスは✕になる。
    var failed: Bool { used >= limit }
}

@Observable
@MainActor
final class HomeViewModel {
    /// 今日実行対象になっているルーティンの一覧。
    private(set) var todayRoutines: [Routine] = []

    /// Routine.id → 今日の進捗(0.0〜1.0 と内訳)。
    private(set) var routineProgressById: [UUID: RoutineTodayProgress] = [:]
    /// Routine.id → そのルーティンの連続達成回数(履歴から計算)。
    private(set) var routineStreakById: [UUID: Int] = [:]

    /// 今日完了しているルーティン数 / 今日対象のルーティン総数。
    var todayCompletedCount: Int {
        todayRoutines.filter { routineProgressById[$0.id]?.isCompletedToday == true }.count
    }
    var todayTotalCount: Int { todayRoutines.count }

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

    var newBlockedBehaviorTitle: String = ""
    var newBlockedBehaviorLimitPeriod: BlockedBehaviorLimitPeriod = .day
    var newBlockedBehaviorLimitCount: Int = 1

    /// 「みんなのざこ速報」に出す項目(いまは自分の記録だけ。最大3件)。
    private(set) var zakoBulletinItems: [ZakoBulletinItem] = []

    /// ルーティンが完了した直後に、完了演出へ渡す表示データが入る。閉じる時は `clearCompletion()`。
    private(set) var completionContext: RoutineCompletionContext?

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
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

        if let behavior = dependencies.blockedBehaviorRepository.fetchActive() {
            dependencies.blockedBehaviorRepository.autoEvaluate(behavior)
        }
        currentBehavior = dependencies.blockedBehaviorRepository.fetchActive()
        masteredBehaviors = dependencies.blockedBehaviorRepository.fetchMastered()
        zakoBulletinItems = Self.buildBulletin(routines: allRoutines, sessions: sessions, behavior: currentBehavior)
        rescheduleNotifications()
    }

    /// 「みんなのざこ速報」の項目を、自分の最近の記録から組み立てる(最大3件)。
    static func buildBulletin(
        routines: [Routine],
        sessions: [RoutineSession],
        behavior: BlockedBehavior?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ZakoBulletinItem] {
        let who = AppSettingsStore.userDisplayName
        let titleById = Dictionary(routines.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        var entries: [(date: Date, line: String)] = []

        for session in sessions where session.status == .completed {
            guard let completedAt = session.completedAt,
                  let title = titleById[session.routineId] else { continue }
            entries.append((completedAt, "\(who)が \(title) を達成しました！"))
        }

        if let behavior, behavior.usageInCurrentPeriod(now: now) >= behavior.effectiveLimit,
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

    // MARK: - 今日の約束

    /// 約束カードの消費状況。
    func promiseUsage(for behavior: BlockedBehavior, now: Date = .now) -> PromiseUsage {
        PromiseUsage(
            used: behavior.usageInCurrentPeriod(now: now),
            limit: behavior.effectiveLimit,
            periodLabel: behavior.limitPeriod.currentUnitLabel
        )
    }

    /// 約束カードのタップで「1回消費」する。
    func consumePromise(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.consume(behavior)
        reload()
    }

    /// 現在挑戦中の項目が無い(未着手 or 卒業済み)場合のみ、新しい「やらないこと」を追加できる。
    var canAddBlockedBehavior: Bool {
        dependencies?.blockedBehaviorRepository.canAddNew() ?? false
    }

    func addBlockedBehavior() {
        guard let dependencies, canAddBlockedBehavior else { return }
        let title = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        dependencies.blockedBehaviorRepository.create(
            title: title,
            limitPeriod: newBlockedBehaviorLimitPeriod,
            limitCount: max(0, newBlockedBehaviorLimitCount)
        )
        newBlockedBehaviorTitle = ""
        newBlockedBehaviorLimitPeriod = .day
        newBlockedBehaviorLimitCount = 0
        reload()
    }

    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        title: String,
        limitPeriod: BlockedBehaviorLimitPeriod,
        limitCount: Int
    ) {
        guard let dependencies else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            title: trimmed.isEmpty ? behavior.title : trimmed,
            limitPeriod: limitPeriod,
            limitCount: max(0, limitCount)
        )
        reload()
    }

    func deleteMasteredBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.delete(behavior)
        reload()
    }

    // MARK: - ルーティン

    func deleteRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        dependencies.routineRepository.delete(routine)
        reload()
    }

    /// ルーティンをタップした時: 1ステップ進める(0ステップなら完了)。完了したら完了演出を出す。
    func advanceRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        guard todayProgress(for: routine).isCompletedToday == false else { return }
        let result = dependencies.routineCompletionService.advance(routine: routine)
        reload()
        if result.didComplete {
            completionContext = RoutineCompletionContext(
                routineTitle: routine.title,
                currentStreak: result.currentStreak
            )
        }
    }

    /// 完了演出を閉じる。
    func clearCompletion() {
        completionContext = nil
    }

    /// 中断中(完了していない)のセッションの現在ステップ名。無ければ nil。
    func inProgressStepTitle(for routine: Routine) -> String? {
        guard let dependencies else { return nil }
        guard let session = dependencies.sessionRepository.fetchActiveSession(routineId: routine.id) else { return nil }
        guard let stepId = session.currentStepId else { return nil }
        return routine.orderedSteps.first { $0.id == stepId }?.title
    }

    /// 中立 App Intent「今日のルーティンを開く」の遷移先。今日ぶんで未完了の先頭、無ければ先頭。
    func firstPendingTodayRoutine() -> Routine? {
        todayRoutines.first { routineProgressById[$0.id]?.isCompletedToday != true } ?? todayRoutines.first
    }

    // MARK: - helpers

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

    /// 今日実行対象のルーティンを、開始予定時刻→作成日順で返す。
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
}
