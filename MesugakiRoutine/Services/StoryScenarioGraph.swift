import Foundation

enum StoryScenarioGraphError: LocalizedError, Equatable {
    case emptyScenario(String)
    case duplicateNodeId(String)
    case duplicateLineOrder(Int)
    case nodeNotInScenario(String)
    case danglingTarget(fromNodeId: String, targetNodeId: String)
    case automaticCycle([String])

    var errorDescription: String? {
        switch self {
        case .emptyScenario(let scenarioId):
            return "Scenario \(scenarioId) has no nodes."
        case .duplicateNodeId(let nodeId):
            return "Scenario contains duplicate node id \(nodeId)."
        case .duplicateLineOrder(let order):
            return "Scenario contains duplicate line order \(order)."
        case .nodeNotInScenario(let nodeId):
            return "Node \(nodeId) does not belong to this scenario."
        case .danglingTarget(let fromNodeId, let targetNodeId):
            return "Node \(fromNodeId) points to missing node \(targetNodeId)."
        case .automaticCycle(let nodeIds):
            return "Automatic traversal entered a cycle: \(nodeIds.joined(separator: " -> "))."
        }
    }
}

/// Directed graph view over one scenario.
///
/// Explicit CMS links win over line order. All target lookup is scoped to this
/// scenario, so an accidentally duplicated/cross-scenario node id cannot jump
/// into unrelated content.
struct StoryScenarioGraph {
    let scenario: StoryScenario
    let orderedNodes: [StoryNode]

    private let nodesById: [String: StoryNode]
    private let orderedIndexById: [String: Int]

    init(scenario: StoryScenario) throws {
        guard !scenario.nodes.isEmpty else {
            throw StoryScenarioGraphError.emptyScenario(scenario.scenarioId)
        }

        let ordered = scenario.nodes.sorted {
            if $0.lineOrder != $1.lineOrder { return $0.lineOrder < $1.lineOrder }
            return $0.nodeId.localizedStandardCompare($1.nodeId) == .orderedAscending
        }
        var ids: [String: StoryNode] = [:]
        var lineOrders = Set<Int>()
        for node in ordered {
            guard ids[node.nodeId] == nil else {
                throw StoryScenarioGraphError.duplicateNodeId(node.nodeId)
            }
            guard lineOrders.insert(node.lineOrder).inserted else {
                throw StoryScenarioGraphError.duplicateLineOrder(node.lineOrder)
            }
            ids[node.nodeId] = node
        }

        self.scenario = scenario
        orderedNodes = ordered
        nodesById = ids
        orderedIndexById = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.nodeId, $0.offset) }
        )
    }

    var firstNode: StoryNode { orderedNodes[0] }

    func node(id: String) -> StoryNode? {
        nodesById[id]
    }

    func isVisible(_ node: StoryNode, phase: Int) -> Bool {
        if let minPhase = node.minPhase, phase < minPhase { return false }
        if let maxPhase = node.maxPhase, phase > maxPhase { return false }
        return true
    }

    /// First phase-visible entry node, following normal links through any
    /// filtered nodes. A cycle made entirely of filtered nodes is recoverable.
    func firstVisibleNode(phase: Int) throws -> StoryNode? {
        try resolveVisible(from: firstNode, phase: phase)
    }

    /// Returns the immediate successor before phase filtering.
    ///
    /// When a choice is supplied its `next_node_id` has highest precedence,
    /// followed by the choice node's `next_node_id`, then line-order fallback.
    func successor(
        after node: StoryNode,
        selectedChoice: StoryChoice? = nil
    ) throws -> StoryNode? {
        guard let index = orderedIndexById[node.nodeId] else {
            throw StoryScenarioGraphError.nodeNotInScenario(node.nodeId)
        }

        if let target = selectedChoice?.nextNodeId ?? node.nextNodeId {
            guard let resolved = nodesById[target] else {
                throw StoryScenarioGraphError.danglingTarget(
                    fromNodeId: node.nodeId,
                    targetNodeId: target
                )
            }
            return resolved
        }

        let nextIndex = index + 1
        return orderedNodes.indices.contains(nextIndex) ? orderedNodes[nextIndex] : nil
    }

    /// Recovery-only successor that ignores explicit edges. The player uses
    /// this after reporting a dangling CMS target so one bad id does not make
    /// the remainder of an otherwise linear scenario unreadable.
    func lineOrderSuccessor(after node: StoryNode) throws -> StoryNode? {
        guard let index = orderedIndexById[node.nodeId] else {
            throw StoryScenarioGraphError.nodeNotInScenario(node.nodeId)
        }
        let nextIndex = index + 1
        return orderedNodes.indices.contains(nextIndex) ? orderedNodes[nextIndex] : nil
    }

    func nextVisibleLineOrderNode(after node: StoryNode, phase: Int) throws -> StoryNode? {
        var cursor = try lineOrderSuccessor(after: node)
        while let candidate = cursor {
            if isVisible(candidate, phase: phase) { return candidate }
            cursor = try lineOrderSuccessor(after: candidate)
        }
        return nil
    }

    func firstVisibleLineOrderNode(phase: Int) -> StoryNode? {
        orderedNodes.first { isVisible($0, phase: phase) }
    }

    /// Returns the next phase-visible node. Invisible nodes are traversed using
    /// their own `next_node_id` or line order; the graph never invents a choice.
    func nextVisibleNode(
        after node: StoryNode,
        selectedChoice: StoryChoice? = nil,
        phase: Int
    ) throws -> StoryNode? {
        let immediate = try successor(after: node, selectedChoice: selectedChoice)
        return try resolveVisible(from: immediate, phase: phase)
    }

    /// Validates every explicit edge currently present in the scenario.
    /// Choice edges are passed separately because choice groups live outside a
    /// scenario in the generated contract.
    func validateExplicitTargets(choiceGroups: [String: [StoryChoice]]) throws {
        for node in orderedNodes {
            if let target = node.nextNodeId, nodesById[target] == nil {
                throw StoryScenarioGraphError.danglingTarget(
                    fromNodeId: node.nodeId,
                    targetNodeId: target
                )
            }
            guard let choiceId = node.choiceId else { continue }
            for choice in choiceGroups[choiceId] ?? [] {
                if let target = choice.nextNodeId, nodesById[target] == nil {
                    throw StoryScenarioGraphError.danglingTarget(
                        fromNodeId: node.nodeId,
                        targetNodeId: target
                    )
                }
            }
        }
    }

    private func resolveVisible(from start: StoryNode?, phase: Int) throws -> StoryNode? {
        var cursor = start
        var visited: [String] = []
        var visitedSet = Set<String>()

        while let node = cursor {
            if isVisible(node, phase: phase) { return node }
            guard visitedSet.insert(node.nodeId).inserted else {
                visited.append(node.nodeId)
                throw StoryScenarioGraphError.automaticCycle(visited)
            }
            visited.append(node.nodeId)
            cursor = try successor(after: node)
        }
        return nil
    }
}
