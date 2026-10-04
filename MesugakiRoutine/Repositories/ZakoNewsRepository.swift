import Foundation
import Supabase

@MainActor
protocol ZakoNewsServing {
    func feed(before: ZakoNewsPost?, ids: [UUID]?, mine: Bool) async throws -> [ZakoNewsPost]
    func publish(_ publication: ZakoNewsPublication) async throws -> UUID
    func comment(postID: UUID, text: String) async throws
    func react(postID: UUID, reaction: String?) async throws
    func report(postID: UUID, reason: String) async throws
    func block(postID: UUID) async throws
    func delete(postID: UUID) async throws
    func blocks() async throws -> [ZakoNewsBlock]
    func unblock(blockID: UUID) async throws
}

/// Public client key only. Sessions are persisted by the SDK in Keychain.
/// Auth requests are single-flight; offline refresh must never create a new identity.
@MainActor
final class ZakoNewsRepository: ZakoNewsServing {
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://xlboihwjliebpissioxh.supabase.co")!,
        supabaseKey: "sb_publishable_8E87GiwDHFuJWDkVxLPTBg_eG433h8P"
    )
    private var authentication: Task<Void, Error>?

    private func authenticate() async throws {
        if let authentication { return try await authentication.value }
        let task = Task { @MainActor in
            if client.auth.currentSession == nil {
                _ = try await client.auth.signInAnonymously()
            } else {
                _ = try await client.auth.session
            }
        }
        authentication = task
        defer { authentication = nil }
        try await task.value
    }

    func feed(before: ZakoNewsPost? = nil, ids: [UUID]? = nil, mine: Bool = false) async throws -> [ZakoNewsPost] {
        try await authenticate()
        struct Parameters: Encodable {
            let p_before: Date?
            let p_before_id: UUID?
            let p_limit: Int
            let p_ids: [UUID]?
            let p_mine: Bool
        }
        return try await client.rpc("zako_feed", params: Parameters(
            p_before: before?.createdAt, p_before_id: before?.id,
            p_limit: ids == nil ? ZakoNewsConfiguration.batchSize : 50, p_ids: ids, p_mine: mine
        )).execute().value
    }

    func publish(_ p: ZakoNewsPublication) async throws -> UUID {
        try await authenticate()
        struct Parameters: Encodable {
            let p_source_key: String
            let p_kind: String
            let p_display_name: String
            let p_task_title: String
            let p_occurred_at: Date
        }
        return try await client.rpc("zako_publish", params: Parameters(
            p_source_key: p.sourceKey, p_kind: p.kind, p_display_name: p.displayName,
            p_task_title: p.title, p_occurred_at: p.occurredAt
        )).execute().value
    }
    func comment(postID: UUID, text: String) async throws {
        try await mutate("zako_comment", ["p_post_id": postID.uuidString, "p_comment": text])
    }
    func react(postID: UUID, reaction: String?) async throws {
        try await authenticate()
        // Explicit JSON null is required to remove a reaction.
        let parameters: [String: AnyJSON] = ["p_post_id": .string(postID.uuidString), "p_reaction": reaction.map(AnyJSON.string) ?? .null]
        try await client.rpc("zako_react", params: parameters).execute()
    }
    func report(postID: UUID, reason: String) async throws {
        try await mutate("zako_report", ["p_post_id": postID.uuidString, "p_reason": reason])
    }
    func block(postID: UUID) async throws { try await mutate("zako_block", ["p_post_id": postID.uuidString]) }
    func delete(postID: UUID) async throws { try await mutate("zako_delete", ["p_post_id": postID.uuidString]) }
    func blocks() async throws -> [ZakoNewsBlock] {
        try await authenticate()
        return try await client.rpc("zako_blocks").execute().value
    }
    func unblock(blockID: UUID) async throws { try await mutate("zako_unblock", ["p_block_id": blockID.uuidString]) }
    private func mutate(_ function: String, _ parameters: [String: String]) async throws {
        try await authenticate()
        try await client.rpc(function, params: parameters).execute()
    }
}
