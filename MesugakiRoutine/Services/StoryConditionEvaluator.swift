import Foundation

enum StoryConditionValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var displayValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        }
    }
}

struct StoryConditionResolverKey: Hashable {
    let conditionType: String
    let conditionKey: String

    init(conditionType: String, conditionKey: String) {
        self.conditionType = conditionType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.conditionKey = conditionKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum StoryConditionResolution {
    case value(StoryConditionValue?)
    case unsupported(String)
}

/// Extensible resolver registry. New CMS metrics are added here without
/// changing comparison or event-AND logic.
struct StoryConditionValueProvider {
    typealias Resolver = (StoryCondition, StoryProgressMetrics) -> StoryConditionValue?

    private var exactResolvers: [StoryConditionResolverKey: Resolver] = [:]
    private var typeResolvers: [String: Resolver] = [:]

    mutating func register(
        conditionType: String,
        conditionKey: String,
        resolver: @escaping Resolver
    ) {
        exactResolvers[
            StoryConditionResolverKey(conditionType: conditionType, conditionKey: conditionKey)
        ] = resolver
    }

    mutating func register(conditionType: String, resolver: @escaping Resolver) {
        typeResolvers[Self.normalize(conditionType)] = resolver
    }

    func resolve(
        _ condition: StoryCondition,
        metrics: StoryProgressMetrics
    ) -> StoryConditionResolution {
        let key = StoryConditionResolverKey(
            conditionType: condition.conditionType,
            conditionKey: condition.conditionKey
        )
        if let resolver = exactResolvers[key] {
            return .value(resolver(condition, metrics))
        }
        if let resolver = typeResolvers[Self.normalize(condition.conditionType)] {
            return .value(resolver(condition, metrics))
        }
        return .unsupported(
            "未対応の解放条件: \(condition.conditionType) / \(condition.conditionKey)"
        )
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension StoryConditionValueProvider {
    static var standard: StoryConditionValueProvider {
        var provider = StoryConditionValueProvider()

        for key in ["continuous_days", "streak_days", "streak"] {
            provider.register(conditionType: "streak", conditionKey: key) { _, metrics in
                .number(Double(metrics.continuousDays))
            }
        }

        provider.register(conditionType: "relationship", conditionKey: "trust") { _, metrics in
            .number(Double(metrics.trust))
        }

        // Profile facts and story flags share the key/value persistence layer.
        // The type namespace remains distinct in the CMS and can be separated
        // later without changing the evaluator.
        provider.register(conditionType: "profile") { condition, metrics in
            metrics.profileValues[condition.conditionKey].map(StoryConditionValue.string)
        }
        provider.register(conditionType: "story_flag") { condition, metrics in
            metrics.profileValues[condition.conditionKey].map(StoryConditionValue.string)
        }

        let completedEventResolver: StoryConditionValueProvider.Resolver = { condition, metrics in
            let rawKey = condition.conditionKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let eventId: String
            if ["event_completed", "completed_event"].contains(rawKey) {
                eventId = condition.threshold
            } else {
                eventId = rawKey
            }
            return metrics.completedEventIds.contains(eventId) ? .string(eventId) : nil
        }
        provider.register(
            conditionType: "event",
            conditionKey: "event_completed",
            resolver: completedEventResolver
        )
        provider.register(
            conditionType: "event",
            conditionKey: "completed_event",
            resolver: completedEventResolver
        )
        provider.register(conditionType: "event_completed", resolver: completedEventResolver)

        // A cumulative resolver is intentionally absent: the current Routine
        // repository discards old timestamps and cannot supply a truthful
        // lifetime total. Adding one is a registry entry once that metric exists.
        return provider
    }
}

struct StoryConditionEvaluation: Identifiable, Equatable {
    let condition: StoryCondition
    let current: String?
    let threshold: String
    let satisfied: Bool
    let displayText: String
    let diagnostic: String?

    var id: String { condition.id }
}

struct StoryEventEvaluation: Identifiable, Equatable {
    let eventId: String
    let conditions: [StoryConditionEvaluation]
    let accessDecision: StoryAccessDecision

    var id: String { eventId }
    var conditionsSatisfied: Bool { conditions.allSatisfy(\.satisfied) }
    var isSatisfied: Bool { conditionsSatisfied && accessDecision.isAllowed }
    var diagnostics: [String] { conditions.compactMap(\.diagnostic) }
}

/// Pure evaluator for one event. Persistence of a satisfied result belongs to
/// `StoryUnlockService`.
struct StoryConditionEvaluator {
    let valueProvider: StoryConditionValueProvider
    let accessPolicy: any StoryAccessPolicy

    init(
        valueProvider: StoryConditionValueProvider = .standard,
        accessPolicy: any StoryAccessPolicy = AllowAllStoryAccessPolicy()
    ) {
        self.valueProvider = valueProvider
        self.accessPolicy = accessPolicy
    }

    func evaluate(
        event: StoryEvent,
        metrics: StoryProgressMetrics
    ) -> StoryEventEvaluation {
        StoryEventEvaluation(
            eventId: event.eventId,
            conditions: event.conditions.map { evaluate(condition: $0, metrics: metrics) },
            accessDecision: accessPolicy.decision(for: event)
        )
    }

    func evaluate(
        condition: StoryCondition,
        metrics: StoryProgressMetrics
    ) -> StoryConditionEvaluation {
        switch valueProvider.resolve(condition, metrics: metrics) {
        case .unsupported(let diagnostic):
            return result(
                condition: condition,
                current: nil,
                satisfied: false,
                diagnostic: diagnostic
            )
        case .value(let current):
            let comparison = compare(
                current: current,
                operator: condition.operator,
                threshold: condition.threshold
            )
            return result(
                condition: condition,
                current: current,
                satisfied: comparison.satisfied,
                diagnostic: comparison.diagnostic
            )
        }
    }

    private func result(
        condition: StoryCondition,
        current: StoryConditionValue?,
        satisfied: Bool,
        diagnostic: String?
    ) -> StoryConditionEvaluation {
        let currentText = current?.displayValue
        return StoryConditionEvaluation(
            condition: condition,
            current: currentText,
            threshold: condition.threshold,
            satisfied: satisfied,
            displayText: displayText(
                condition: condition,
                current: currentText,
                satisfied: satisfied
            ),
            diagnostic: diagnostic
        )
    }
}

private extension StoryConditionEvaluator {
    struct ComparisonOutcome {
        let satisfied: Bool
        let diagnostic: String?
    }

    func compare(
        current: StoryConditionValue?,
        operator op: StoryConditionOperator,
        threshold: String
    ) -> ComparisonOutcome {
        if op == .exists {
            return ComparisonOutcome(satisfied: current != nil, diagnostic: nil)
        }
        guard let current else {
            return ComparisonOutcome(satisfied: false, diagnostic: "条件値を取得できません")
        }
        guard case .unknown(let rawOperator) = op else {
            return compareKnown(current: current, operator: op, threshold: threshold)
        }
        return ComparisonOutcome(
            satisfied: false,
            diagnostic: "未対応の比較演算子: \(rawOperator)"
        )
    }

    func compareKnown(
        current: StoryConditionValue,
        operator op: StoryConditionOperator,
        threshold: String
    ) -> ComparisonOutcome {
        let lhs = current.displayValue
        let rhs = threshold

        let comparison: ComparisonResult
        if let lhsNumber = Double(lhs.trimmingCharacters(in: .whitespacesAndNewlines)),
           let rhsNumber = Double(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) {
            if lhsNumber < rhsNumber {
                comparison = .orderedAscending
            } else if lhsNumber > rhsNumber {
                comparison = .orderedDescending
            } else {
                comparison = .orderedSame
            }
        } else {
            comparison = lhs.compare(rhs, options: .literal)
        }

        let satisfied: Bool
        switch op {
        case .equal:
            satisfied = comparison == .orderedSame
        case .notEqual:
            satisfied = comparison != .orderedSame
        case .greaterThan:
            satisfied = comparison == .orderedDescending
        case .greaterThanOrEqual:
            satisfied = comparison != .orderedAscending
        case .lessThan:
            satisfied = comparison == .orderedAscending
        case .lessThanOrEqual:
            satisfied = comparison != .orderedDescending
        case .exists:
            satisfied = true
        case .unknown(let rawOperator):
            return ComparisonOutcome(
                satisfied: false,
                diagnostic: "未対応の比較演算子: \(rawOperator)"
            )
        }
        return ComparisonOutcome(satisfied: satisfied, diagnostic: nil)
    }

    func displayText(
        condition: StoryCondition,
        current: String?,
        satisfied: Bool
    ) -> String {
        let currentText = current ?? "—"
        let symbol: String
        switch condition.operator {
        case .equal: symbol = "="
        case .notEqual: symbol = "≠"
        case .greaterThan: symbol = ">"
        case .greaterThanOrEqual: symbol = "≥"
        case .lessThan: symbol = "<"
        case .lessThanOrEqual: symbol = "≤"
        case .exists: symbol = "あり"
        case .unknown(let value): symbol = value
        }

        let prefix = satisfied ? "達成" : "未達成"
        if condition.conditionType == "streak" && condition.conditionKey == "continuous_days" {
            return "\(prefix): 継続 \(currentText)日 \(symbol) \(condition.threshold)日"
        }
        if ["event_completed", "completed_event"].contains(condition.conditionKey) {
            return "\(prefix): 前提イベント \(condition.threshold)"
        }
        if condition.operator == .exists {
            return "\(prefix): \(condition.conditionKey) \(symbol)"
        }
        return "\(prefix): \(condition.conditionKey) \(currentText) \(symbol) \(condition.threshold)"
    }
}
