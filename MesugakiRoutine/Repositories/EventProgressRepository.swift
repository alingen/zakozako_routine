import Foundation
import SwiftData

/// イベントの解放/完了状態(EventProgress)の永続化を担当する。
@MainActor
final class EventProgressRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [EventProgress] {
        let descriptor = FetchDescriptor<EventProgress>()
        return (try? context.fetch(descriptor)) ?? []
    }

    func progress(for eventId: String) -> EventProgress? {
        fetchAll().first { $0.eventId == eventId }
    }

    func isUnlocked(_ eventId: String) -> Bool { progress(for: eventId)?.isUnlocked ?? false }
    func isCompleted(_ eventId: String) -> Bool { progress(for: eventId)?.isCompleted ?? false }

    /// 条件を満たしたイベントを解放状態にする(すでに解放済みなら何もしない)。強制開始はしない。
    func markUnlocked(eventId: String) {
        let progress = fetchOrCreate(eventId)
        guard progress.unlockedAt == nil else { return }
        progress.unlockedAt = .now
        progress.updatedAt = .now
        save()
    }

    /// イベントを最後まで再生し終えた時に呼ぶ。
    func markCompleted(eventId: String) {
        let progress = fetchOrCreate(eventId)
        if progress.unlockedAt == nil { progress.unlockedAt = .now }
        progress.completedAt = .now
        progress.updatedAt = .now
        save()
    }

    /// 「あとにする」を押した時に呼ぶ(状態は消さず、押した日時だけ記録する)。
    func markDeferred(eventId: String) {
        let progress = fetchOrCreate(eventId)
        progress.deferredAt = .now
        progress.updatedAt = .now
        save()
    }

    /// デバッグ用: すべてのイベント進行状態を消す。
    func resetAll() {
        for progress in fetchAll() {
            context.delete(progress)
        }
        save()
    }

    private func fetchOrCreate(_ eventId: String) -> EventProgress {
        if let existing = progress(for: eventId) { return existing }
        let created = EventProgress(eventId: eventId)
        context.insert(created)
        save()
        return created
    }

    private func save() {
        try? context.save()
    }
}
