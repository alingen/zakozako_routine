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
    /// チェックボックスの塗り具合 0.0〜1.0(残り / 上限)。満タンからスタートし、タップで減る。
    var fraction: Double { limit > 0 ? Double(remaining) / Double(limit) : 0 }
    /// 上限に達した(残り0)= 失敗。チェックボックスは✕になる。
    var failed: Bool { used >= limit }
}

@Observable
@MainActor
final class HomeViewModel {
    /// 今日対象になっている約束の一覧。
    private(set) var todayRoutines: [Routine] = []
    /// Routine.id → 現在の期間の進捗。
    private(set) var routineProgressById: [UUID: RoutineTodayProgress] = [:]
    /// Routine.id → 連続達成日数。
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

    var newBlockedBehaviorTitle: String = ""
    var newHabitPeriod: HabitPeriod = .day
    var newBlockedBehaviorLimitCount: Int = 1

    /// 「みんなのざこ速報」に出す項目(いまは自分の記録だけ。最大3件)。
    private(set) var zakoBulletinItems: [ZakoBulletinItem] = []

    /// 約束が完了した直後に、完了演出へ渡す表示データが入る。閉じる時は `clearCompletion()`。
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

        var progressMap: [UUID: RoutineTodayProgress] = [:]
        var streakMap: [UUID: Int] = [:]
        for routine in allRoutines {
            progressMap[routine.id] = routine.todayProgress()
            streakMap[routine.id] = RoutineStreak.currentStreak(routine: routine)
        }
        routineProgressById = progressMap
        routineStreakById = streakMap

        if let behavior = dependencies.blockedBehaviorRepository.fetchActive() {
            dependencies.blockedBehaviorRepository.autoEvaluate(behavior)
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
        var entries: [(date: Date, line: String)] = []

        for routine in routines where routine.isComplete(now: now) {
            guard let last = routine.progressEvents.max(),
                  calendar.isDate(last, inSameDayAs: now) else { continue }
            entries.append((last, "\(who)が \(routine.title) を達成しました！"))
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

    // MARK: - やらないこと

    func promiseUsage(for behavior: BlockedBehavior, now: Date = .now) -> PromiseUsage {
        PromiseUsage(
            used: behavior.usageInCurrentPeriod(now: now),
            limit: behavior.effectiveLimit,
            periodLabel: behavior.limitPeriod.currentUnitLabel
        )
    }

    func consumePromise(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.consume(behavior)
        reload()
    }

    var canAddBlockedBehavior: Bool {
        dependencies?.blockedBehaviorRepository.canAddNew() ?? false
    }

    func addBlockedBehavior() {
        guard let dependencies, canAddBlockedBehavior else { return }
        let title = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        dependencies.blockedBehaviorRepository.create(
            title: title,
            limitPeriod: newHabitPeriod,
            limitCount: max(1, newBlockedBehaviorLimitCount)
        )
        newBlockedBehaviorTitle = ""
        newHabitPeriod = .day
        newBlockedBehaviorLimitCount = 1
        reload()
    }

    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        title: String,
        limitPeriod: HabitPeriod,
        limitCount: Int
    ) {
        guard let dependencies else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            title: trimmed.isEmpty ? behavior.title : trimmed,
            limitPeriod: limitPeriod,
            limitCount: max(1, limitCount)
        )
        reload()
    }

    func deleteMasteredBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.delete(behavior)
        reload()
    }

    // MARK: - 約束(Routine)

    func deleteRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        dependencies.routineRepository.delete(routine)
        reload()
    }

    /// 約束をタップした時: 1回進める。目標に達したら完了演出を出す。
    func advanceRoutine(_ routine: Routine) {
        guard let dependencies else { return }
        let wasComplete = routine.isComplete()
        dependencies.routineRepository.recordProgress(routine)
        reload()
        if !wasComplete && routine.isComplete() {
            completionContext = RoutineCompletionContext(
                routineTitle: routine.title,
                currentStreak: RoutineStreak.currentStreak(routine: routine)
            )
        }
    }

    func clearCompletion() {
        completionContext = nil
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
