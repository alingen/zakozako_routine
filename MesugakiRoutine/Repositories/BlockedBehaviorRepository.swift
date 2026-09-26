import Foundation
import SwiftData

enum BlockedBehaviorFailureRecordResult: Equatable {
    case recorded
    case alreadyRecorded
}

enum BlockedBehaviorRepositoryError: LocalizedError {
    case inactiveBehavior
    case invalidTrackingKind
    case screenTimeSignalNotReady

    var errorDescription: String? {
        switch self {
        case .inactiveBehavior:
            return "この項目は現在挑戦中ではありません。"
        case .invalidTrackingKind:
            return "この項目はスクリーンタイムで計測されていません。"
        case .screenTimeSignalNotReady:
            return "スクリーンタイムの1日がまだ終了していません。"
        }
    }
}

/// 「やらないこと」リストの永続化を担当する。
/// 悪習慣を1つずつ潰していく設計のため、同時に挑戦中(`isActive == true`)になれるのは1件のみ。
/// 14日間の連続達成で「卒業」(`masteredAt`が入る)し、次の1件を追加できるようになる。
@MainActor
final class BlockedBehaviorRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [BlockedBehavior] {
        let descriptor = FetchDescriptor<BlockedBehavior>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetch(id: UUID) -> BlockedBehavior? {
        let descriptor = FetchDescriptor<BlockedBehavior>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// 現在挑戦中の項目(あれば1件)。
    func fetchActive() -> BlockedBehavior? {
        fetchAll().first { $0.isActive && $0.masteredAt == nil }
    }

    /// 14日間守り切って卒業した項目。新しい順。
    func fetchMastered() -> [BlockedBehavior] {
        fetchAll()
            .filter { $0.masteredAt != nil }
            .sorted { ($0.masteredAt ?? .distantPast) > ($1.masteredAt ?? .distantPast) }
    }

    /// 新しい項目を追加できるか(現在挑戦中の項目が無い場合のみ)。
    func canAddNew() -> Bool {
        fetchActive() == nil
    }

    @discardableResult
    func create(
        title: String,
        iconName: String? = nil,
        limitPeriod: HabitPeriod = .day,
        limitCount: Int = 0,
        trackingKind: BlockedBehaviorTrackingKind = .manual,
        screenTimeLimitMinutes: Int? = nil,
        screenTimeSelectionData: Data? = nil,
        shareToZakoNews: Bool = false
    ) -> BlockedBehavior? {
        guard canAddNew() else { return nil }
        let behavior = BlockedBehavior(
            title: title,
            iconName: iconName,
            limitPeriod: limitPeriod,
            limitCount: limitCount,
            trackingKind: trackingKind,
            screenTimeLimitMinutes: screenTimeLimitMinutes,
            screenTimeSelectionData: screenTimeSelectionData
        )
        behavior.shareToZakoNews = shareToZakoNews
        context.insert(behavior)
        do {
            try context.save()
            return behavior
        } catch {
            context.delete(behavior)
            return nil
        }
    }

    /// 挑戦中の項目の設定だけを更新する。進捗・連続日数・作成日は維持する。
    @discardableResult
    func update(
        _ behavior: BlockedBehavior,
        title: String,
        iconName: String?,
        limitPeriod: HabitPeriod,
        limitCount: Int,
        trackingKind: BlockedBehaviorTrackingKind,
        screenTimeLimitMinutes: Int?,
        screenTimeSelectionData: Data?,
        now: Date = .now,
        shareToZakoNews: Bool? = nil
    ) -> Bool {
        behavior.title = title
        if let shareToZakoNews { behavior.shareToZakoNews = shareToZakoNews }
        behavior.iconName = iconName
        behavior.limitPeriod = limitPeriod
        behavior.limitCount = max(limitCount, 1)
        behavior.trackingKind = trackingKind
        if let screenTimeLimitMinutes {
            behavior.screenTimeLimitMinutes = screenTimeLimitMinutes
        }
        behavior.screenTimeSelectionData = screenTimeSelectionData
        behavior.updatedAt = now

        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// ユーザーが「負けました」を確定した時、その1回だけを消費ログとして記録する。
    /// 現在期間の上限に達した後は何も変更しない。
    @discardableResult
    func recordFailure(
        _ behavior: BlockedBehavior,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> BlockedBehaviorFailureRecordResult {
        guard behavior.isActive, behavior.masteredAt == nil else {
            throw BlockedBehaviorRepositoryError.inactiveBehavior
        }

        let used = behavior.usageInCurrentPeriod(now: now, calendar: calendar)
        guard used < behavior.effectiveLimit else {
            return .alreadyRecorded
        }

        try performMutation {
            behavior.usageEvents.append(now)
            context.insert(UserActionEvent(
                eventType: .prohibitionFailed,
                targetType: .prohibition,
                targetID: behavior.id,
                occurredAt: now
            ))
            // 配列が無限に伸びないよう、直近3か月より古いイベントは捨てる(判定に不要)。
            if let cutoff = calendar.date(byAdding: .month, value: -3, to: now) {
                behavior.usageEvents.removeAll { $0 < cutoff }
            }
            behavior.updatedAt = now
        }
        return .recorded
    }

    /// 「負けそう…」を押した事実。日別の勝敗や消費回数は変えない。
    @discardableResult
    func recordUrge(_ behavior: BlockedBehavior, now: Date = .now) throws -> UserActionEvent {
        guard behavior.isActive, behavior.masteredAt == nil else {
            throw BlockedBehaviorRepositoryError.inactiveBehavior
        }
        let event = UserActionEvent(eventType: .prohibitionUrge, targetType: .prohibition,
            targetID: behavior.id, occurredAt: now)
        try performMutation { context.insert(event) }
        return event
    }

    /// Device Activity 拡張から届いた、上限超過または1日の監視完了を保存する。
    /// 監視完了が確認できた日だけを達成に数え、同じ日の上限超過は必ず達成より優先する。
    @discardableResult
    func recordScreenTimeSignal(
        _ signal: ScreenTimeMonitorSignal,
        for behavior: BlockedBehavior,
        processedAt: Date = .now,
        calendar: Calendar = .current
    ) throws -> Bool {
        guard behavior.trackingKind == .screenTime else {
            throw BlockedBehaviorRepositoryError.invalidTrackingKind
        }
        guard behavior.isActive || behavior.masteredAt != nil else {
            throw BlockedBehaviorRepositoryError.inactiveBehavior
        }

        // 拡張機能が監視開始時に確定した絶対時刻を、そのまま日付キーとして使う。
        // 取り込み時のタイムゾーンで再計算すると、旅行時に別日へ移るため正規化しない。
        let signalDay = signal.appDayStart
        // 作成前の古いOS通知が残っていた場合は、処理済みにしてよい通知として無視する。
        guard signal.occurredAt >= behavior.createdAt else { return false }

        if signal.kind == .intervalCompleted {
            let currentDay = AppDay.startOfDay(for: processedAt, calendar: calendar)
            guard signalDay < currentDay else {
                // 境界の直前に届いた終了通知は、日付が切り替わった次回取り込みまで残す。
                throw BlockedBehaviorRepositoryError.screenTimeSignalNotReady
            }
            if #unavailable(iOS 17.4) {
                let createdDay = AppDay.startOfDay(for: behavior.createdAt, calendar: calendar)
                if signalDay == createdDay {
                    // 17.0〜17.3は登録前の当日利用を含められないため、作成日は達成に数えない。
                    return false
                }
            }
        }

        let hasOtherActiveBehavior = fetchAll().contains {
            $0.id != behavior.id && $0.isActive && $0.masteredAt == nil
        }
        var didChange = false

        try performMutation {
            switch signal.kind {
            case .thresholdExceeded:
                let alreadyFailed = behavior.screenTimeFailedDays.contains(signalDay)
                if !alreadyFailed {
                    behavior.screenTimeFailedDays.append(signalDay)
                    let failureDate = calendar.date(
                        byAdding: .second,
                        value: 1,
                        to: signalDay
                    ) ?? signalDay
                    behavior.usageEvents.append(failureDate)
                    didChange = true
                }

            case .intervalCompleted:
                let alreadyVerified = behavior.screenTimeVerifiedDays.contains(signalDay)
                if !alreadyVerified {
                    behavior.screenTimeVerifiedDays.append(signalDay)
                    didChange = true
                }
            }

            guard didChange else { return }

            if let cutoff = calendar.date(byAdding: .month, value: -3, to: processedAt) {
                behavior.usageEvents.removeAll { $0 < cutoff }
                behavior.screenTimeVerifiedDays.removeAll { $0 < cutoff }
                behavior.screenTimeFailedDays.removeAll { $0 < cutoff }
            }
            reconcileScreenTimeProgress(
                behavior,
                processedAt: processedAt,
                hasOtherActiveBehavior: hasOtherActiveBehavior,
                calendar: calendar
            )
            behavior.updatedAt = processedAt
        }
        return didChange
    }

    /// 前日までの未評価の日を順に自動判定し、連続日数・卒業を更新する。手動チェックインの置き換え。
    /// - Returns: 今回新たに「達成」と判定された日数(呼び出し側で信頼度・累積回数を加算するのに使う)。
    @discardableResult
    func autoEvaluate(_ behavior: BlockedBehavior, calendar: Calendar = .current, now: Date = .now) -> Int {
        // Screen Time は拡張機能が intervalDidEnd を返した日だけ評価する。
        // 「失敗通知がない」だけで成功にすると、権限解除・監視停止を達成扱いにしてしまう。
        guard behavior.trackingKind == .manual else { return 0 }

        let today = AppDay.startOfDay(for: now, calendar: calendar)
        let createdDay = AppDay.startOfDay(for: behavior.createdAt, calendar: calendar)

        var cursor: Date
        if let last = behavior.lastCheckInDate {
            cursor = calendar.date(byAdding: .day, value: 1, to: AppDay.startOfDay(for: last, calendar: calendar)) ?? today
        } else {
            // 一度も評価していない場合は、遡りすぎないよう最大でも「昨日」から。
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        cursor = max(cursor, createdDay)

        var keptDays = 0
        var didEvaluate = false
        while cursor < today {
            didEvaluate = true
            if behavior.exceededLimit(on: cursor, calendar: calendar) {
                behavior.currentStreakDays = 0
            } else {
                behavior.currentStreakDays += 1
                keptDays += 1
                if behavior.currentStreakDays >= BlockedBehavior.masteryStreakDays, behavior.masteredAt == nil {
                    behavior.masteredAt = now
                    behavior.isActive = false
                }
            }
            behavior.lastCheckInDate = cursor
            if behavior.masteredAt != nil { break }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }

        if didEvaluate {
            behavior.updatedAt = now
            save()
        }
        return keptDays
    }

    @discardableResult
    func delete(_ behavior: BlockedBehavior) -> Bool {
        context.delete(behavior)
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    // MARK: - デバッグ用(自動判定の動作確認)

    /// 現在挑戦中の項目の日付を1日ぶん巻き戻し、次回 reload で「昨日ぶん」の自動判定が走るようにする。
    func debugAgePromiseByOneDay(calendar: Calendar = .current) {
        guard let active = fetchActive() else { return }
        if let created = calendar.date(byAdding: .day, value: -1, to: active.createdAt) {
            active.createdAt = created
        }
        if let last = active.lastCheckInDate,
           let shifted = calendar.date(byAdding: .day, value: -1, to: last) {
            active.lastCheckInDate = shifted
        }
        save()
    }

    private func save() {
        try? context.save()
    }

    private func reconcileScreenTimeProgress(
        _ behavior: BlockedBehavior,
        processedAt: Date,
        hasOtherActiveBehavior: Bool,
        calendar: Calendar
    ) {
        let verifiedDays = Set(behavior.screenTimeVerifiedDays)
        let failedDays = Set(behavior.screenTimeFailedDays)
        let recordedDays = verifiedDays.union(failedDays).sorted()

        var streak = 0
        for day in recordedDays {
            if failedDays.contains(day) {
                streak = 0
            } else if verifiedDays.contains(day) {
                streak += 1
            }
        }

        behavior.currentStreakDays = streak
        behavior.lastCheckInDate = recordedDays.last

        if streak >= BlockedBehavior.masteryStreakDays {
            if behavior.masteredAt == nil {
                behavior.masteredAt = processedAt
            }
            behavior.isActive = false
        } else if behavior.masteredAt != nil {
            // 卒業直前の日に遅延した超過通知が届いた場合も、履歴から正しく戻す。
            behavior.masteredAt = nil
            // すでに次の挑戦が始まっていれば、そちらを優先し旧項目は終了済みの履歴にする。
            behavior.isActive = !hasOtherActiveBehavior
        }
    }

    private func performMutation(_ mutation: () throws -> Void) throws {
        do {
            try context.transaction {
                try mutation()
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
