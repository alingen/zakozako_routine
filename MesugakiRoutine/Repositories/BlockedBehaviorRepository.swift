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
    func create(title: String, reason: String, alternativeAction: String, triggerText: String, counterMessage: String) -> BlockedBehavior {
        let behavior = BlockedBehavior(
            title: title,
            triggerText: triggerText,
            counterMessage: counterMessage,
            reason: reason,
            alternativeAction: alternativeAction
        )
        context.insert(behavior)
        save()
        return behavior
    }

    /// 検出ワード・理由・代替行動・検出時間帯だけをまとめて更新する(ホーム画面の詳細編集シート用)。
    func updateDetails(
        _ behavior: BlockedBehavior,
        reason: String,
        alternativeAction: String,
        triggerText: String,
        activeStartMinute: Int?,
        activeEndMinute: Int?
    ) {
        behavior.reason = reason
        behavior.alternativeAction = alternativeAction
        behavior.triggerText = triggerText
        behavior.activeStartMinute = activeStartMinute
        behavior.activeEndMinute = activeEndMinute
        behavior.updatedAt = .now
        save()
    }

    func delete(_ behavior: BlockedBehavior) {
        context.delete(behavior)
        save()
    }

    /// まだ前日分の「まもれた/まもれなかった」記録が無ければ、確認すべき対象を返す。
    /// (挑戦を始めた翌日以降、かつ前日分が未記録の場合のみ)
    func pendingCheckIn(calendar: Calendar = .current, now: Date = .now) -> BlockedBehavior? {
        guard let active = fetchActive() else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        guard calendar.startOfDay(for: active.createdAt) <= yesterday else { return nil }
        if let last = active.lastCheckInDate, calendar.startOfDay(for: last) >= yesterday {
            return nil
        }
        return active
    }

    /// 前日分の「まもれた/まもれなかった」を記録する。まもれた場合は連続日数を+1し、
    /// 14日に達したら卒業(`masteredAt`設定・`isActive`解除)させ、次の項目を追加できるようにする。
    /// まもれなかった場合は連続日数を0にリセットし、同じ項目への挑戦を続ける。
    func recordCheckIn(_ behavior: BlockedBehavior, protected: Bool, calendar: Calendar = .current, now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        behavior.lastCheckInDate = yesterday
        if protected {
            behavior.currentStreakDays += 1
            if behavior.currentStreakDays >= BlockedBehavior.masteryStreakDays {
                behavior.masteredAt = now
                behavior.isActive = false
            }
        } else {
            behavior.currentStreakDays = 0
        }
        behavior.updatedAt = now
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

    // MARK: - デバッグ用(前日チェックインの動作確認)

    /// 現在挑戦中の項目を「前日ぶんが未記録」の状態に戻し、ホームの約束チェックインUIを再表示させる。
    /// 作成日を2日前まで巻き戻し、最終チェックイン日をクリアする。
    func debugMakeCheckInPending(calendar: Calendar = .current, now: Date = .now) {
        guard let active = fetchActive() else { return }
        active.createdAt = calendar.date(byAdding: .day, value: -2, to: now) ?? active.createdAt
        active.lastCheckInDate = nil
        save()
    }

    private func save() {
        try? context.save()
    }
}
