import Foundation
import Observation

/// One store per app session, shared by Home, detail and Settings. No network in init.
@MainActor @Observable
final class ZakoNewsStore {
    static let shared = ZakoNewsStore(repository: ZakoNewsRepository())
    let repository: any ZakoNewsServing
    private(set) var rotation = ZakoNewsRotation()
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var pendingPublications: [ZakoNewsPublication]
    private let defaults: UserDefaults
    private let pendingKey = "zako_news_pending_v1"
    private var isSending = false
    private var lastFetch: Date?
    private var cursor: ZakoNewsPost?
    private var exhausted = false

    init(repository: any ZakoNewsServing, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        pendingPublications = defaults.data(forKey: pendingKey)
            .flatMap { try? JSONDecoder().decode([ZakoNewsPublication].self, from: $0) } ?? []
    }

    func enqueue(_ publication: ZakoNewsPublication?) {
        guard let publication else { return }
        guard ZakoNewsText.canShare(title: publication.title, name: publication.displayName) else {
            errorMessage = "記録は保存しました。" + ZakoNewsText.validationMessage
            return
        }
        guard !pendingPublications.contains(where: { $0.id == publication.id }) else { return }
        pendingPublications.append(publication)
        persistPending()
        Task { await sendPending() }
    }

    func cancelPending(for itemID: UUID) {
        pendingPublications.removeAll { $0.itemID == itemID }
        persistPending()
    }

    func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        pendingPublications.removeAll { $0.occurredAt < .now.addingTimeInterval(-ZakoNewsConfiguration.retentionSeconds) }
        persistPending()
        while let publication = pendingPublications.first {
            do {
                let id = try await repository.publish(publication)
                pendingPublications.removeAll { $0.id == publication.id }
                persistPending()
                // 送れた自分の投稿はホームの先頭に出す(ひとことはその行から添えられる)。あとは通常の自動送りに任せる。
                if let post = try? await repository.feed(before: nil, ids: [id], mine: false).first {
                    rotation.showFirst(post)
                }
                errorMessage = nil
            } catch {
                errorMessage = "記録は保存済みです。速報を共有できませんでした。接続後に再送できます。"
                return
            }
        }
    }

    /// At most one fetch cycle per minute; rotations are purely local.
    func refreshIfNeeded(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || lastFetch.map({ Date.now.timeIntervalSince($0) >= ZakoNewsConfiguration.refreshSeconds }) ?? true else { return }
        isLoading = true
        lastFetch = .now
        defer { isLoading = false }
        do {
            try await validateCachedPosts()
            let newest = try await repository.feed(before: nil, ids: nil, mine: false)
            rotation.append(newest)
            if cursor == nil { cursor = newest.last; exhausted = newest.count < ZakoNewsConfiguration.batchSize }
            if rotation.pending.count < 5, !exhausted, let cursor {
                let older = try await repository.feed(before: cursor, ids: nil, mine: false)
                rotation.append(older)
                self.cursor = older.last ?? cursor
                exhausted = older.count < ZakoNewsConfiguration.batchSize
            }
            if pendingPublications.isEmpty { errorMessage = nil }
        } catch {
            errorMessage = "速報を読み込めませんでした。習慣の記録はそのまま使えます。"
        }
        await sendPending()
    }

    func rotate() {
        rotation.expire(now: .now)
        rotation.advance()
    }
    func validateCachedPosts() async throws {
        let ids = (rotation.visible + rotation.pending).map(\.id)
        guard !ids.isEmpty else { return }
        // Cache is bounded (< two batches); one request, not per-post queries.
        let valid = try await repository.feed(before: nil, ids: ids, mine: false)
        rotation.reconcile(valid)
    }
    func refreshPost(_ id: UUID) async throws -> ZakoNewsPost? {
        let post = try await repository.feed(before: nil, ids: [id], mine: false).first
        if let post {
            rotation.replace(post)
        } else { remove(id) }
        return post
    }
    func remove(_ id: UUID) {
        rotation.remove(id)
    }
    func didBlock() async throws {
        // Resolve all cached IDs server-side. No client-side author identifier needed.
        do { try await validateCachedPosts() }
        catch { rotation.clearCache() } // Fail closed after a successful block.
        cursor = nil; exhausted = false
        await refreshIfNeeded(force: true)
    }
    private func persistPending() { defaults.set(try? JSONEncoder().encode(pendingPublications), forKey: pendingKey) }
}
