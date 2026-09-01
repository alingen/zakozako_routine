import Foundation
import SwiftData

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
        reason: String,
        alternativeAction: String,
        triggerText: String,
        counterMessage: String,
        limitPeriod: BlockedBehaviorLimitPeriod = .day,
        limitCount: Int = 0
    ) -> BlockedBehavior {
        let behavior = BlockedBehavior(
            title: title,
            triggerText: triggerText,
            counterMessage: counterMessage,
            reason: reason,
            alternativeAction: alternativeAction,
            limitPeriod: limitPeriod,
            limitCount: limitCount
        )
        context.insert(behavior)
        save()
        return behavior
    }

    /// 検出ワード・理由・代替行動・検出時間帯・回数制限をまとめて更新する(詳細編集シート用)。
    func updateDetails(
        _ behavior: BlockedBehavior,
        reason: String,
        alternativeAction: String,
        triggerText: String,
        activeStartMinute: Int?,
        activeEndMinute: Int?,
        limitPeriod: BlockedBehaviorLimitPeriod,
        limitCount: Int
    ) {
        behavior.reason = reason
        behavior.alternativeAction = alternativeAction
        behavior.triggerText = triggerText
        behavior.activeStartMinute = activeStartMinute
        behavior.activeEndMinute = activeEndMinute
        behavior.limitPeriod = limitPeriod
        behavior.limitCount = limitCount
        behavior.updatedAt = .now
        save()
    }

    /// カードタップで「1回消費」する。
    func consume(_ behavior: BlockedBehavior, now: Date = .now, calendar: Calendar = .current) {
        behavior.usageEvents.append(now)
        // 配列が無限に伸びないよう、直近3か月より古いイベントは捨てる(判定に不要)。
        if let cutoff = calendar.date(byAdding: .month, value: -3, to: now) {
            behavior.usageEvents.removeAll { $0 < cutoff }
        }
        behavior.updatedAt = now
        save()
    }

    /// 前日までの未評価の日を順に自動判定し、連続日数・卒業を更新する。手動チェックインの置き換え。
    /// - Returns: 今回新たに「達成」と判定された日数(呼び出し側で信頼度・累積回数を加算するのに使う)。
    @discardableResult
    func autoEvaluate(_ behavior: BlockedBehavior, calendar: Calendar = .current, now: Date = .now) -> Int {
        let today = calendar.startOfDay(for: now)
        let createdDay = calendar.startOfDay(for: behavior.createdAt)

        var cursor: Date
        if let last = behavior.lastCheckInDate {
            cursor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? today
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

    func delete(_ behavior: BlockedBehavior) {
        context.delete(behavior)
        save()
    }

    /// ユーザー入力テキストが、現在挑戦中の項目にマッチするか(簡易な部分一致 + 時間帯判定)。
    func firstMatch(for text: String, at date: Date = .now) -> BlockedBehavior? {
        guard !text.isEmpty, let behavior = fetchActive() else { return nil }
        guard !behavior.triggerText.isEmpty else { return nil }
        guard text.localizedCaseInsensitiveContains(behavior.triggerText) else { return nil }
        guard behavior.isWithinActiveWindow(at: date) else { return nil }
        return behavior
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
}
