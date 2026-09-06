import Foundation

/// A JSON value used for forward-compatible CMS command arguments.
///
/// `command_args` is intentionally not decoded into one closed enum: adding a
/// command argument in Google Sheets must not make an older app fail to load the
/// entire story catalog.
enum JSONValue: Codable, Hashable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted(.number.grouping(.never))
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value) where value.rounded() == value:
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}

// MARK: - Forward-compatible CMS values

enum StoryScenarioType: Hashable, Codable {
    case daily
    case smallEvent
    case middleEvent
    case largeEvent
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "daily": self = .daily
        case "small_event": self = .smallEvent
        case "middle_event": self = .middleEvent
        case "large_event": self = .largeEvent
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .daily: return "daily"
        case .smallEvent: return "small_event"
        case .middleEvent: return "middle_event"
        case .largeEvent: return "large_event"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryEventType: Hashable, Codable {
    case small
    case middle
    case large
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "small_event": self = .small
        case "middle_event": self = .middle
        case "large_event": self = .large
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .small: return "small_event"
        case .middle: return "middle_event"
        case .large: return "large_event"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryMessageType: Hashable, Codable {
    case text
    case choice
    case action
    case image
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "text": self = .text
        case "choice": self = .choice
        case "action": self = .action
        case "image": self = .image
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .text: return "text"
        case .choice: return "choice"
        case .action: return "action"
        case .image: return "image"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryScreenMode: Hashable, Codable {
    case adv
    case chat
    case call
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "adv": self = .adv
        case "chat": self = .chat
        case "call": self = .call
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .adv: return "adv"
        case .chat: return "chat"
        case .call: return "call"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryUIVariant: Hashable, Codable {
    case titleCard
    case narration
    case dialogue
    case sceneTransition
    case incomingCall
    case recording
    case audioMessage
    case callEnd
    case modal
    case imageMessage
    case typing
    case outgoingCall
    case callConnected
    case beat
    case monologue
    case cg
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "title_card": self = .titleCard
        case "narration": self = .narration
        case "dialogue": self = .dialogue
        case "scene_transition": self = .sceneTransition
        case "incoming_call": self = .incomingCall
        case "recording": self = .recording
        case "audio_message": self = .audioMessage
        case "call_end": self = .callEnd
        case "modal": self = .modal
        case "image_message": self = .imageMessage
        case "typing": self = .typing
        case "outgoing_call": self = .outgoingCall
        case "call_connected": self = .callConnected
        case "beat": self = .beat
        case "monologue": self = .monologue
        case "cg": self = .cg
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .titleCard: return "title_card"
        case .narration: return "narration"
        case .dialogue: return "dialogue"
        case .sceneTransition: return "scene_transition"
        case .incomingCall: return "incoming_call"
        case .recording: return "recording"
        case .audioMessage: return "audio_message"
        case .callEnd: return "call_end"
        case .modal: return "modal"
        case .imageMessage: return "image_message"
        case .typing: return "typing"
        case .outgoingCall: return "outgoing_call"
        case .callConnected: return "call_connected"
        case .beat: return "beat"
        case .monologue: return "monologue"
        case .cg: return "cg"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryCategory: Hashable, Codable {
    case main
    case sub
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "main": self = .main
        case "sub": self = .sub
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .main: return "main"
        case .sub: return "sub"
        case .unknown(let value): return value
        }
    }

    var displayName: String {
        switch self {
        case .main: return "メインストーリー"
        case .sub: return "サブストーリー"
        case .unknown: return "ストーリー"
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StoryConditionOperator: Hashable, Codable {
    case equal
    case notEqual
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case exists
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "eq": self = .equal
        case "ne": self = .notEqual
        case "gt": self = .greaterThan
        case "gte": self = .greaterThanOrEqual
        case "lt": self = .lessThan
        case "lte": self = .lessThanOrEqual
        case "exists": self = .exists
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .equal: return "eq"
        case .notEqual: return "ne"
        case .greaterThan: return "gt"
        case .greaterThanOrEqual: return "gte"
        case .lessThan: return "lt"
        case .lessThanOrEqual: return "lte"
        case .exists: return "exists"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Generated story content

struct StoryContentBundle: Codable, Hashable {
    let scenarios: [StoryScenario]
    let choiceGroups: [StoryChoiceGroup]
    let events: [StoryEvent]
}

struct StoryScenario: Codable, Hashable, Identifiable {
    let scenarioId: String
    let scenarioType: StoryScenarioType
    let nodes: [StoryNode]

    var id: String { scenarioId }
}

struct StoryNode: Codable, Hashable, Identifiable {
    let nodeId: String
    let lineOrder: Int
    let speaker: String
    let messageType: StoryMessageType
    let text: String?
    let choiceId: String?
    let nextNodeId: String?
    let saveKey: String?
    let saveValue: String?
    let assetId: String?
    let minPhase: Int?
    let maxPhase: Int?
    let speakerName: String?
    let background: String?
    let portrait: String?
    let cg: String?
    let screenMode: StoryScreenMode?
    let uiVariant: StoryUIVariant?
    let command: String?
    let commandArgs: JSONValue?
    let notes: String?

    var id: String { nodeId }

    init(
        nodeId: String,
        lineOrder: Int,
        speaker: String,
        messageType: StoryMessageType,
        text: String? = nil,
        choiceId: String? = nil,
        nextNodeId: String? = nil,
        saveKey: String? = nil,
        saveValue: String? = nil,
        assetId: String? = nil,
        minPhase: Int? = nil,
        maxPhase: Int? = nil,
        speakerName: String? = nil,
        background: String? = nil,
        portrait: String? = nil,
        cg: String? = nil,
        screenMode: StoryScreenMode? = nil,
        uiVariant: StoryUIVariant? = nil,
        command: String? = nil,
        commandArgs: JSONValue? = nil,
        notes: String? = nil
    ) {
        self.nodeId = nodeId
        self.lineOrder = lineOrder
        self.speaker = speaker
        self.messageType = messageType
        self.text = text
        self.choiceId = choiceId
        self.nextNodeId = nextNodeId
        self.saveKey = saveKey
        self.saveValue = saveValue
        self.assetId = assetId
        self.minPhase = minPhase
        self.maxPhase = maxPhase
        self.speakerName = speakerName
        self.background = background
        self.portrait = portrait
        self.cg = cg
        self.screenMode = screenMode
        self.uiVariant = uiVariant
        self.command = command
        self.commandArgs = commandArgs
        self.notes = notes
    }
}

struct StoryChoiceGroup: Codable, Hashable, Identifiable {
    let choiceId: String
    let choices: [StoryChoice]

    var id: String { choiceId }
}

struct StoryChoice: Codable, Hashable, Identifiable {
    let choiceOrder: Int
    let label: String
    let nextNodeId: String?
    let saveKey: String?
    let saveValue: String?
    let requiredKey: String?
    let requiredOperator: StoryConditionOperator?
    let requiredValue: String?
    let notes: String?

    /// Stable inside its choice group. Callers that combine groups should also
    /// include the group's `choiceId` in their identity.
    var id: Int { choiceOrder }

    init(
        choiceOrder: Int,
        label: String,
        nextNodeId: String? = nil,
        saveKey: String? = nil,
        saveValue: String? = nil,
        requiredKey: String? = nil,
        requiredOperator: StoryConditionOperator? = nil,
        requiredValue: String? = nil,
        notes: String? = nil
    ) {
        self.choiceOrder = choiceOrder
        self.label = label
        self.nextNodeId = nextNodeId
        self.saveKey = saveKey
        self.saveValue = saveValue
        self.requiredKey = requiredKey
        self.requiredOperator = requiredOperator
        self.requiredValue = requiredValue
        self.notes = notes
    }
}

struct StoryCondition: Codable, Hashable, Identifiable {
    let conditionType: String
    let conditionKey: String
    let `operator`: StoryConditionOperator
    let threshold: String

    var id: String {
        "\(conditionType)|\(conditionKey)|\(`operator`.rawValue)|\(threshold)"
    }
}

struct StoryEvent: Codable, Hashable, Identifiable {
    let eventId: String
    let eventType: StoryEventType
    let title: String
    let entryScenarioId: String
    let priority: Int
    let repeatable: Bool
    let cooldownDays: Int
    let background: String?
    let advancesToPhase: Int?
    let chapterId: String?
    let episodeOrder: Int?
    let storyCategory: StoryCategory?
    let conditions: [StoryCondition]
    let notes: String?

    var id: String { eventId }
}

// MARK: - Access policy extension point

enum StoryAccessDecision: Equatable {
    case allowed
    case denied(reason: String?)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Product access (for example a future premium entitlement) is deliberately
/// separate from CMS unlock conditions. There is no premium column today, so
/// the default policy grants access without inventing a Day-based rule.
protocol StoryAccessPolicy {
    func decision(for event: StoryEvent) -> StoryAccessDecision
}

struct AllowAllStoryAccessPolicy: StoryAccessPolicy {
    func decision(for event: StoryEvent) -> StoryAccessDecision { .allowed }
}
