import Foundation

enum ZakoNewsConfiguration {
    static let commentLimit = 30
    static let titleLimit = 80
    static let nameLimit = 10
    static let batchSize = 20
    static let homeCount = 3
    /// 「みんなもやってるな〜」と眺める程度の速さにする。
    static let rotationSeconds: Double = 8
    static let refreshSeconds: Double = 60
    static let retentionSeconds: Double = 7 * 24 * 60 * 60
}

enum ZakoNewsText {
    static func isValid(_ value: String, limit: Int, allowEmpty: Bool = false) -> Bool {
        // Match Postgres char_length (Unicode scalars rather than extended graphemes).
        guard value.unicodeScalars.count <= limit,
              allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { return false }
        return value.range(of: #"(?i)(https?://|www\.|[\p{L}\p{N}_-]+\.[a-z]{2,}([/:\s]|$))"#,
                           options: .regularExpression) == nil
    }

    static func canShare(title: String, name: String = AppSettingsStore.userName) -> Bool {
        isValid(title, limit: ZakoNewsConfiguration.titleLimit)
            && isValid(name.isEmpty ? "名無し" : name, limit: ZakoNewsConfiguration.nameLimit)
    }
    /// 長さは入力欄で守るので、ここに来るのは名前か項目名に URL などが含まれるときだけ。
    static let validationMessage = "名前か項目名にURLなどが含まれるため、ざこ速報には共有しませんでした。"
}

enum ZakoNewsReaction: String, Codable, CaseIterable, Identifiable {
    case cheer, tease, strong
    var id: String { rawValue }
    var title: String {
        switch self { case .cheer: "がんばれ♡"; case .tease: "ざ〜こ♡"; case .strong: "つよ〜♡" }
    }
}

enum ZakoNewsReportReason: String, CaseIterable, Identifiable {
    case inappropriate, privacy, harassment, spam, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inappropriate: "不適切な内容"
        case .privacy: "個人情報"
        case .harassment: "嫌がらせ"
        case .spam: "スパム"
        case .other: "その他"
        }
    }
}

struct ZakoNewsPost: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: String
    let displayName: String
    let taskTitle: String
    var comment: String
    let occurredAt: Date
    let createdAt: Date
    let isMine: Bool
    var cheerCount: Int
    var teaseCount: Int
    var strongCount: Int
    var myReaction: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, comment
        case displayName = "display_name", taskTitle = "task_title"
        case occurredAt = "occurred_at", createdAt = "created_at", isMine = "is_mine"
        case cheerCount = "cheer_count", teaseCount = "tease_count", strongCount = "strong_count"
        case myReaction = "my_reaction"
    }
    var line: String { subjectText + resultText }
    /// 定型で長くなりがちな「○○おにいさんが」。一覧ではここで改行する。
    var subjectText: String { "\(displayName)おにいさんが" }
    var resultText: String {
        kind == "achievement" ? "「\(taskTitle)」を達成しました！" : "「\(taskTitle)」に負けました…"
    }
    var relativeTime: String {
        let seconds = max(0, Date.now.timeIntervalSince(occurredAt))
        switch seconds {
        case ..<60: return "たった今"
        case ..<3600: return "\(Int(seconds / 60))分前"
        case ..<86400: return "\(Int(seconds / 3600))時間前"
        default: return "\(Int(seconds / 86400))日前"
        }
    }
    func count(for reaction: ZakoNewsReaction) -> Int {
        switch reaction { case .cheer: cheerCount; case .tease: teaseCount; case .strong: strongCount }
    }
}

struct ZakoNewsBlock: Decodable, Identifiable {
    let id: UUID // Block record ID, never an auth user ID.
    let display_name: String
}

/// Pending delivery metadata only; not a second habit/completion model.
struct ZakoNewsPublication: Codable, Identifiable, Equatable {
    var id: String { sourceKey }
    let sourceKey: String
    let itemID: UUID
    let kind: String
    let displayName: String
    let title: String
    let occurredAt: Date

    @MainActor static func achievement(_ routine: Routine, now: Date) -> Self? {
        guard routine.shareToZakoNews, routine.isComplete(now: now) else { return nil }
        let window = routine.period.window(containing: now, calendar: .current)
        // One result per rule/period. Undo then re-check does not produce a second post.
        let source = "routine:\(routine.id):\(routine.currentRuleStartedAt.timeIntervalSince1970):\(window.start.timeIntervalSince1970)"
        return make(source: source, itemID: routine.id, kind: "achievement", title: routine.title, now: now)
    }

    @MainActor static func failure(_ behavior: BlockedBehavior, now: Date) -> Self? {
        guard behavior.shareToZakoNews else { return nil }
        // Exactly the date persisted in usageEvents; retry reuses the entire envelope.
        return make(source: "failure:\(behavior.id):\(now.timeIntervalSince1970)",
                    itemID: behavior.id, kind: "failure", title: behavior.title, now: now)
    }

    private static func make(source: String, itemID: UUID, kind: String, title: String, now: Date) -> Self {
        // 制限を入れる前に一般で長い名前を入れていても共有できるよう、上限で切って送る。
        let trimmed = AppSettingsStore.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(ZakoNewsConfiguration.nameLimit)))
        return Self(sourceKey: source, itemID: itemID, kind: kind,
                    displayName: name.isEmpty ? "名無し" : name, title: title, occurredAt: now)
    }
}

/// Session-only rotation. Seen IDs survive Home navigation and buffer refills.
struct ZakoNewsRotation {
    private(set) var visible: [ZakoNewsPost] = []
    private(set) var pending: [ZakoNewsPost] = []
    private(set) var seen: Set<UUID> = []

    mutating func append(_ posts: [ZakoNewsPost]) {
        var known = seen.union(pending.map(\.id))
        for post in posts where known.insert(post.id).inserted { pending.append(post) }
        pending = Array(pending.prefix(ZakoNewsConfiguration.batchSize * 2))
        while visible.count < ZakoNewsConfiguration.homeCount && !pending.isEmpty {
            let next = pending.removeFirst()
            visible.append(next)
            seen.insert(next.id)
        }
    }
    mutating func advance() {
        guard !pending.isEmpty else { return }
        let next = pending.removeFirst()
        seen.insert(next.id)
        visible.insert(next, at: 0)
        visible = Array(visible.prefix(ZakoNewsConfiguration.homeCount))
    }
    /// 指定の投稿をすぐ先頭に出す(自分の投稿を送れた直後など)。表示中の件数は変えない。
    mutating func showFirst(_ post: ZakoNewsPost) {
        visible.removeAll { $0.id == post.id }
        pending.removeAll { $0.id == post.id }
        seen.insert(post.id)
        visible.insert(post, at: 0)
        visible = Array(visible.prefix(ZakoNewsConfiguration.homeCount))
    }
    mutating func reconcile(_ allowed: [ZakoNewsPost]) {
        let lookup = Dictionary(uniqueKeysWithValues: allowed.map { ($0.id, $0) })
        visible = visible.compactMap { lookup[$0.id] }
        pending = pending.compactMap { lookup[$0.id] }
    }
    mutating func replace(_ post: ZakoNewsPost) {
        visible = visible.map { $0.id == post.id ? post : $0 }
        pending = pending.map { $0.id == post.id ? post : $0 }
    }
    mutating func remove(_ id: UUID) {
        visible.removeAll { $0.id == id }; pending.removeAll { $0.id == id }
    }
    mutating func clearCache() { visible = []; pending = [] }
    mutating func expire(now: Date) {
        let cutoff = now.addingTimeInterval(-ZakoNewsConfiguration.retentionSeconds)
        visible.removeAll { $0.occurredAt <= cutoff }; pending.removeAll { $0.occurredAt <= cutoff }
    }
}
