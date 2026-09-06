import Foundation
import Observation

typealias StoryPlayerSleep = (UInt64) async throws -> Void
typealias StoryPlayerLogger = (String) -> Void
typealias StoryPlayerNow = () -> Date

enum StoryPlayerError: LocalizedError, Equatable {
    case invalidScenario(String)
    case invalidCheckpoint(String)
    case unavailableChoice(String)
    case noAvailableChoices(String)
    case automaticCycle([String])
    case automaticTraversalLimit(Int)

    var errorDescription: String? {
        switch self {
        case .invalidScenario(let detail):
            return "シナリオを開始できません: \(detail)"
        case .invalidCheckpoint(let detail):
            return "保存済みの再生位置を復元できません: \(detail)"
        case .unavailableChoice(let label):
            return "選択肢「\(label)」は現在選べません"
        case .noAvailableChoices(let choiceId):
            return "選択可能な項目がありません: \(choiceId)"
        case .automaticCycle(let nodeIds):
            return "自動進行の循環を停止しました: \(nodeIds.joined(separator: " → "))"
        case .automaticTraversalLimit(let limit):
            return "自動進行が上限（\(limit)ノード）に達したため停止しました"
        }
    }
}

/// UI-independent scenario engine. Views observe only the presentation state
/// below and send user intents back through the async control methods.
@MainActor
@Observable
final class StoryPlayer {
    let title: String

    private(set) var currentNode: StoryNode?
    private(set) var currentMode: StoryScreenMode
    private(set) var visibleChatNodes: [StoryNode] = []
    private(set) var backgroundAssetID: String?
    private(set) var portraitAssetID: String?
    private(set) var cgAssetID: String?
    private(set) var availableChoices: [StoryChoice] = []
    private(set) var isTyping = false
    private(set) var isModalPresented = false
    private(set) var isCompleted = false
    private(set) var recoverableError: String?

    /// Additional presentation facts retained for future renderers. Existing
    /// renderers can continue reading `currentNode.assetId` directly.
    private(set) var callState: StoryCallPresentationState?
    private(set) var activeAudioAssetID: String?

    @ObservationIgnored private let scenario: StoryScenario
    @ObservationIgnored private let event: StoryEvent?
    @ObservationIgnored private let playbackKey: String
    @ObservationIgnored private let contentRepository: StoryContentRepository
    @ObservationIgnored private let stateRepository: StoryStateRepository
    @ObservationIgnored private let commandDispatcher: StoryCommandDispatcher
    @ObservationIgnored private let sleep: StoryPlayerSleep
    @ObservationIgnored private let logger: StoryPlayerLogger
    @ObservationIgnored private let now: StoryPlayerNow
    @ObservationIgnored private let graph: StoryScenarioGraph?
    @ObservationIgnored private let graphConstructionError: String?
    @ObservationIgnored private let initialMode: StoryScreenMode

    @ObservationIgnored private var checkpoint: StoryPlaybackCheckpoint?
    @ObservationIgnored private var currentPhase = 0
    @ObservationIgnored private var operationGeneration: UInt64 = 0
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var isClosed = false

    init(
        scenario: StoryScenario,
        event: StoryEvent? = nil,
        playbackKey: String,
        contentRepository: StoryContentRepository,
        stateRepository: StoryStateRepository,
        commandDispatcher: StoryCommandDispatcher = StoryCommandDispatcher(),
        sleep: @escaping StoryPlayerSleep = { milliseconds in
            guard milliseconds > 0 else { return }
            try await Task<Never, Never>.sleep(nanoseconds: milliseconds * 1_000_000)
        },
        logger: @escaping StoryPlayerLogger = { _ in },
        now: @escaping StoryPlayerNow = Date.init
    ) {
        self.scenario = scenario
        self.event = event
        self.playbackKey = playbackKey
        self.contentRepository = contentRepository
        self.stateRepository = stateRepository
        self.commandDispatcher = commandDispatcher
        self.sleep = sleep
        self.logger = logger
        self.now = now

        let defaultMode: StoryScreenMode = scenario.scenarioType == .daily ? .chat : .adv
        initialMode = defaultMode
        currentMode = defaultMode
        title = event?.title ?? (scenario.scenarioType == .daily ? "今日の会話" : scenario.scenarioId)
        backgroundAssetID = event?.background

        do {
            graph = try StoryScenarioGraph(scenario: scenario)
            graphConstructionError = nil
        } catch {
            graph = nil
            graphConstructionError = error.localizedDescription
        }
    }

    /// Loads a durable checkpoint. Previously visited presentation commands
    /// are replayed without delays or persistence writes before resuming.
    func start() async {
        guard let token = beginOperation() else { return }
        isClosed = false
        resetPresentation(clearError: true)
        defer { endOperation(token) }

        do {
            guard let graph else {
                throw StoryPlayerError.invalidScenario(
                    graphConstructionError ?? scenario.scenarioId
                )
            }
            if let event {
                try stateRepository.markOpened(eventId: event.eventId, at: now())
            }
            currentPhase = try stateRepository.relationshipPhase()

            var restored: StoryPlaybackCheckpoint?
            do {
                restored = try stateRepository.checkpoint(for: playbackKey)
            } catch {
                report(StoryPlayerError.invalidCheckpoint(error.localizedDescription).localizedDescription)
                restored = try stateRepository.restartPlayback(
                    playbackKey: playbackKey,
                    scenarioId: scenario.scenarioId,
                    at: now()
                )
            }

            if let restored, restored.scenarioId != scenario.scenarioId {
                report(
                    StoryPlayerError.invalidCheckpoint(
                        "scenario \(restored.scenarioId) は現在の \(scenario.scenarioId) と一致しません"
                    ).localizedDescription
                )
                self.checkpoint = try stateRepository.restartPlayback(
                    playbackKey: playbackKey,
                    scenarioId: scenario.scenarioId,
                    at: now()
                )
            } else {
                checkpoint = restored ?? StoryPlaybackCheckpoint(
                    playbackKey: playbackKey,
                    scenarioId: scenario.scenarioId,
                    updatedAt: now()
                )
            }

            guard var checkpoint else { return }
            restorePresentation(from: checkpoint, graph: graph)

            if checkpoint.isCompleted {
                currentNode = nil
                availableChoices = []
                isCompleted = true
                return
            }

            // The last transition and `complete` are separate repository
            // calls so the final node's save pair can be committed first. If
            // the process stopped in that narrow gap, finish monotonically
            // instead of replaying the story from the beginning.
            if checkpoint.currentNodeId == nil, !checkpoint.visitedNodeIds.isEmpty {
                report("中断された読了処理を復旧しました")
                try complete(checkpoint: checkpoint)
                return
            }

            let target: StoryNode
            var currentWasReplayed = false
            if let nodeId = checkpoint.currentNodeId,
               let savedNode = graph.node(id: nodeId),
               graph.isVisible(savedNode, phase: currentPhase) {
                target = savedNode
                currentWasReplayed = checkpoint.visitedNodeIds.last == nodeId
            } else {
                if let nodeId = checkpoint.currentNodeId {
                    report(
                        StoryPlayerError.invalidCheckpoint(
                            "node \(nodeId) が見つからないか、現在のphaseでは表示できません"
                        ).localizedDescription
                    )
                    checkpoint = try stateRepository.restartPlayback(
                        playbackKey: playbackKey,
                        scenarioId: scenario.scenarioId,
                        at: now()
                    )
                    self.checkpoint = checkpoint
                    resetPresentation(clearError: false)
                }
                guard let first = try firstPlayableNode(in: graph) else {
                    try complete(checkpoint: checkpoint)
                    return
                }
                target = first
            }

            try await drive(
                from: target,
                firstNodeWasReplayed: currentWasReplayed,
                token: token
            )
        } catch is CancellationError {
            // Cancellation is an expected consequence of closing/restarting.
        } catch {
            guard operationGeneration == token else { return }
            report(error.localizedDescription)
        }
    }

    /// Advances a user-paused text/image/audio node.
    func advance(expectedNodeId: String? = nil) async {
        guard expectedNodeId == nil || currentNode?.nodeId == expectedNodeId else { return }
        guard !isCompleted, !isClosed, let token = beginOperation() else { return }
        defer { endOperation(token) }

        guard let node = currentNode else { return }
        guard !isModalPresented else {
            report("モーダルを閉じてから次へ進んでください")
            return
        }
        guard node.choiceId == nil, node.messageType != .choice else {
            let choiceId = node.choiceId ?? node.nodeId
            report(StoryPlayerError.noAvailableChoices(choiceId).localizedDescription)
            return
        }

        do {
            let next = try persistTransition(after: node, selectedChoice: nil)
            guard operationGeneration == token else { return }
            if let next {
                try await drive(from: next, firstNodeWasReplayed: false, token: token)
            } else if let checkpoint {
                try complete(checkpoint: checkpoint)
            }
        } catch is CancellationError {
            // Cancellation is an expected consequence of closing/restarting.
        } catch {
            guard operationGeneration == token else { return }
            report(error.localizedDescription)
        }
    }

    func selectChoice(_ choice: StoryChoice, expectedNodeId: String? = nil) async {
        guard expectedNodeId == nil || currentNode?.nodeId == expectedNodeId else { return }
        guard !isCompleted, !isClosed, let token = beginOperation() else { return }
        defer { endOperation(token) }

        guard let node = currentNode,
              let choiceId = node.choiceId,
              availableChoices.contains(choice) else {
            report(StoryPlayerError.unavailableChoice(choice.label).localizedDescription)
            return
        }
        guard !isModalPresented else {
            report("モーダルを閉じてから選択してください")
            return
        }

        do {
            let next = try persistTransition(
                after: node,
                selectedChoice: choice,
                choiceId: choiceId
            )
            guard operationGeneration == token else { return }
            availableChoices = []
            if let next {
                try await drive(from: next, firstNodeWasReplayed: false, token: token)
            } else if let checkpoint {
                try complete(checkpoint: checkpoint)
            }
        } catch is CancellationError {
            // Cancellation is an expected consequence of closing/restarting.
        } catch {
            guard operationGeneration == token else { return }
            report(error.localizedDescription)
        }
    }

    /// A modal is a blocking story node. Dismissing it consumes that node and
    /// continues traversal; ordinary `advance()` remains guarded while open.
    func dismissModal(expectedNodeId: String? = nil) async {
        guard expectedNodeId == nil || currentNode?.nodeId == expectedNodeId else { return }
        guard !isCompleted, !isClosed, let token = beginOperation() else { return }
        defer { endOperation(token) }
        guard isModalPresented, let node = currentNode else { return }

        isModalPresented = false
        do {
            let next = try persistTransition(after: node, selectedChoice: nil)
            guard operationGeneration == token else { return }
            if let next {
                try await drive(from: next, firstNodeWasReplayed: false, token: token)
            } else if let checkpoint {
                try complete(checkpoint: checkpoint)
            }
        } catch is CancellationError {
            // Cancellation is an expected consequence of closing/restarting.
        } catch {
            guard operationGeneration == token else { return }
            report(error.localizedDescription)
        }
    }

    /// Clears playback only; event read/unlock state and memory unlocks remain.
    func restart() async {
        let token = beginReplacingOperation()
        isClosed = false
        resetPresentation(clearError: true)
        defer { endOperation(token) }

        do {
            guard let graph else {
                throw StoryPlayerError.invalidScenario(
                    graphConstructionError ?? scenario.scenarioId
                )
            }
            if let event {
                try stateRepository.markOpened(eventId: event.eventId, at: now())
            }
            currentPhase = try stateRepository.relationshipPhase()
            checkpoint = try stateRepository.restartPlayback(
                playbackKey: playbackKey,
                scenarioId: scenario.scenarioId,
                at: now()
            )
            guard let first = try firstPlayableNode(in: graph) else {
                if let checkpoint { try complete(checkpoint: checkpoint) }
                return
            }
            try await drive(from: first, firstNodeWasReplayed: false, token: token)
        } catch is CancellationError {
            // Cancellation is an expected consequence of a newer operation.
        } catch {
            guard operationGeneration == token else { return }
            report(error.localizedDescription)
        }
    }

    func reread() async {
        await restart()
    }

    /// Invalidates an in-flight wait. Entry checkpoints are already durable,
    /// so closing requires no additional write.
    func close() {
        operationGeneration &+= 1
        isProcessing = false
        isClosed = true
        isModalPresented = false
        availableChoices = []
    }
}

private extension StoryPlayer {
    func drive(
        from firstNode: StoryNode,
        firstNodeWasReplayed: Bool,
        token: UInt64
    ) async throws {
        guard let graph else { return }
        var cursor: StoryNode? = firstNode
        var replayed = firstNodeWasReplayed
        var automaticallyVisited: [String] = []
        var automaticallyVisitedSet = Set<String>()
        let automaticLimit = max(32, graph.orderedNodes.count * 2)

        while let node = cursor {
            guard operationGeneration == token, !isClosed else { return }
            let dispatch = commandDispatcher.dispatch(node: node)
            let resolvedChoices = try choices(for: node)
            let isChoiceNode = node.choiceId != nil || node.messageType == .choice
            var pausesForUser = shouldPauseForUser(on: node, dispatch: dispatch)
            if isChoiceNode, resolvedChoices.isEmpty {
                pausesForUser = false
                report(
                    StoryPlayerError.noAvailableChoices(node.choiceId ?? node.nodeId)
                        .localizedDescription
                )
            }

            if !pausesForUser {
                guard automaticallyVisitedSet.insert(node.nodeId).inserted else {
                    automaticallyVisited.append(node.nodeId)
                    report(StoryPlayerError.automaticCycle(automaticallyVisited).localizedDescription)
                    return
                }
                automaticallyVisited.append(node.nodeId)
                guard automaticallyVisited.count <= automaticLimit else {
                    report(
                        StoryPlayerError.automaticTraversalLimit(automaticLimit).localizedDescription
                    )
                    return
                }
            }

            if replayed {
                currentNode = presentationNode(for: node, dispatch: dispatch)
                availableChoices = resolvedChoices
            } else {
                isModalPresented = false
                activeAudioAssetID = nil
                let displayedNode = presentationNode(for: node, dispatch: dispatch)
                currentNode = displayedNode
                availableChoices = []

                let encounteredCGs = applyPresentation(
                    node: node,
                    dispatch: dispatch,
                    allowTransientEffects: true
                )
                appendVisibleChatNodeIfNeeded(displayedNode)
                availableChoices = resolvedChoices
                try persistEntry(node: node, encounteredCGs: encounteredCGs)
            }

            if let diagnostic = dispatch.diagnostic { report(diagnostic) }
            if pausesForUser { return }

            if !replayed, let waitMilliseconds = waitMilliseconds(in: dispatch) {
                try await sleep(waitMilliseconds)
                guard operationGeneration == token, !isClosed else { return }
            }

            cursor = try persistTransition(after: node, selectedChoice: nil)
            replayed = false
            if cursor == nil, let checkpoint {
                try complete(checkpoint: checkpoint)
                return
            }
        }
    }

    func persistEntry(node: StoryNode, encounteredCGs: Set<String>) throws {
        var updated = checkpoint ?? StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: scenario.scenarioId,
            updatedAt: now()
        )
        updated.currentNodeId = node.nodeId
        updated.visitedNodeIds.append(node.nodeId)
        for assetID in encounteredCGs.sorted()
            where !updated.seenCGAssetIds.contains(assetID) {
            updated.seenCGAssetIds.append(assetID)
        }
        updated.isCompleted = false
        updated.updatedAt = now()
        try stateRepository.saveCheckpoint(updated)
        checkpoint = updated
    }

    func persistTransition(
        after node: StoryNode,
        selectedChoice: StoryChoice?,
        choiceId: String? = nil
    ) throws -> StoryNode? {
        guard var updated = checkpoint else {
            throw StoryPlayerError.invalidCheckpoint("checkpointがありません")
        }

        let profileKey = selectedChoice?.saveKey ?? node.saveKey
        let profileValue = selectedChoice?.saveValue ?? node.saveValue
        let nextPhase = projectedPhase(
            applyingProfileKey: profileKey,
            value: profileValue
        )
        let next = try resolveNext(
            after: node,
            selectedChoice: selectedChoice,
            phase: nextPhase
        )

        updated.currentNodeId = next?.nodeId
        updated.updatedAt = now()

        if let selectedChoice, let choiceId {
            let history = StoryChoiceHistoryEntry(
                nodeId: node.nodeId,
                choiceId: choiceId,
                choiceOrder: selectedChoice.choiceOrder,
                label: selectedChoice.label,
                nextNodeId: selectedChoice.nextNodeId
            )
            updated = try stateRepository.saveChoice(
                history,
                profileKey: profileKey,
                profileValue: profileValue,
                next: updated
            )
        } else {
            try stateRepository.saveCheckpoint(
                updated,
                profileKey: profileKey,
                profileValue: profileValue
            )
        }

        checkpoint = updated
        currentPhase = nextPhase
        return next
    }

    func complete(checkpoint: StoryPlaybackCheckpoint) throws {
        self.checkpoint = try stateRepository.complete(
            event: event,
            checkpoint: checkpoint,
            at: now()
        )
        currentNode = nil
        availableChoices = []
        isModalPresented = false
        isTyping = false
        isCompleted = true
    }
}

private extension StoryPlayer {
    func restorePresentation(
        from checkpoint: StoryPlaybackCheckpoint,
        graph: StoryScenarioGraph
    ) {
        resetPresentation(clearError: false)
        let replayedCurrentIndex: Int? = checkpoint.currentNodeId.flatMap { currentNodeId in
            guard checkpoint.visitedNodeIds.last == currentNodeId else { return nil }
            return checkpoint.visitedNodeIds.indices.last
        }

        for (index, nodeId) in checkpoint.visitedNodeIds.enumerated() {
            guard let node = graph.node(id: nodeId) else {
                report("保存済み経路のnode \(nodeId)をスキップしました")
                continue
            }
            let dispatch = commandDispatcher.dispatch(node: node)
            let displayedNode = presentationNode(for: node, dispatch: dispatch)
            _ = applyPresentation(
                node: node,
                dispatch: dispatch,
                allowTransientEffects: index == replayedCurrentIndex
            )
            appendVisibleChatNodeIfNeeded(displayedNode)
            if index == replayedCurrentIndex { currentNode = displayedNode }
            if let diagnostic = dispatch.diagnostic { report(diagnostic) }
        }

        if let currentNodeId = checkpoint.currentNodeId {
            if currentNode?.nodeId != currentNodeId {
                currentNode = graph.node(id: currentNodeId)
            }
        }
        isCompleted = checkpoint.isCompleted
    }

    /// Applies node fields even when `command` is absent. For scene_change,
    /// command_args may set a mode, but an explicit node.screenMode wins.
    @discardableResult
    func applyPresentation(
        node: StoryNode,
        dispatch: StoryCommandDispatchResult,
        allowTransientEffects: Bool
    ) -> Set<String> {
        var encounteredCGs = Set<String>()

        // A delivered message replaces the transient typing indicator even if
        // the sheet omits an explicit typing_hide row.
        if node.messageType != .action, node.uiVariant != .typing {
            isTyping = false
        }

        if let background = normalized(node.background) {
            backgroundAssetID = background
        }
        if let portrait = normalized(node.portrait) {
            portraitAssetID = portrait
        }
        if let cg = normalized(node.cg) {
            cgAssetID = cg
            encounteredCGs.insert(cg)
        } else if node.uiVariant == .cg, let assetID = normalized(node.assetId) {
            cgAssetID = assetID
            encounteredCGs.insert(assetID)
        }
        if node.uiVariant == .modal, allowTransientEffects {
            isModalPresented = true
        }

        for effect in dispatch.effects {
            switch effect {
            case .setBackground(let assetID):
                backgroundAssetID = assetID
            case .setScreenMode(let mode):
                currentMode = mode
            case .showCG(let assetID):
                cgAssetID = assetID
                encounteredCGs.insert(assetID)
            case .hideCG:
                cgAssetID = nil
            case .setTyping(let value):
                isTyping = value
            case .presentModal:
                if allowTransientEffects { isModalPresented = true }
            case .wait:
                break
            case .setCallState(let state):
                callState = state
            case .playAudio(let assetID), .recordAudio(let assetID):
                if allowTransientEffects { activeAudioAssetID = assetID }
            }
        }

        // The row-level field is the most specific source and therefore wins
        // over scene_change.command_args.screen_mode on the same node.
        if let mode = node.screenMode { currentMode = mode }
        return encounteredCGs
    }

    func choices(for node: StoryNode) throws -> [StoryChoice] {
        guard let choiceId = normalized(node.choiceId) else { return [] }
        let candidates = contentRepository.choices(id: choiceId)
        guard !candidates.isEmpty else {
            report("choice group \(choiceId) が見つかりません")
            return []
        }

        let profileValues = try stateRepository.profileValues()
        let metrics = StoryProgressMetrics(
            continuousDays: 0,
            profileValues: profileValues
        )
        let evaluator = StoryConditionEvaluator()

        return candidates.filter { choice in
            guard let key = normalized(choice.requiredKey) else { return true }
            let comparison = choice.requiredOperator
                ?? (normalized(choice.requiredValue) == nil ? .exists : .equal)
            let condition = StoryCondition(
                conditionType: "profile",
                conditionKey: key,
                operator: comparison,
                threshold: choice.requiredValue ?? ""
            )
            let evaluation = evaluator.evaluate(condition: condition, metrics: metrics)
            if let diagnostic = evaluation.diagnostic {
                report("選択肢「\(choice.label)」: \(diagnostic)")
            }
            return evaluation.satisfied
        }
    }

    func shouldPauseForUser(
        on node: StoryNode,
        dispatch: StoryCommandDispatchResult
    ) -> Bool {
        if dispatch.effects.contains(where: {
            if case .presentModal = $0 { return true }
            return false
        }) {
            return true
        }
        if node.choiceId != nil || node.messageType == .choice { return true }
        if node.messageType == .image { return true }

        // Scene transitions are visible content, not zero-duration state
        // mutations. Pause so the renderer is guaranteed to present them.
        if node.uiVariant == .sceneTransition { return true }

        // An unsupported/malformed command is recoverable, but consuming it
        // automatically could skip a future interaction semantics.
        if normalized(node.command) != nil,
           dispatch.effects.isEmpty,
           dispatch.diagnostic != nil {
            return true
        }

        switch node.uiVariant {
        case .modal, .imageMessage, .audioMessage, .recording, .incomingCall,
             .outgoingCall, .callConnected, .callEnd:
            return true
        case .cg:
            if dispatch.effects.contains(where: {
                if case .hideCG = $0 { return true }
                return false
            }) {
                break
            }
            return true
        default:
            break
        }

        if dispatch.effects.contains(where: {
            switch $0 {
            case .playAudio, .recordAudio: return true
            default: return false
            }
        }) {
            return true
        }

        switch node.messageType {
        case .text, .unknown:
            return true
        case .choice, .image:
            return true
        case .action:
            return false
        }
    }

    func waitMilliseconds(in dispatch: StoryCommandDispatchResult) -> UInt64? {
        for effect in dispatch.effects {
            if case .wait(let milliseconds) = effect { return milliseconds }
        }
        return nil
    }

    /// Existing renderers read audio from `currentNode.assetId`. The CMS keeps
    /// it in command_args for command rows, so decorate only the presentation
    /// copy while retaining the graph node as the source of navigation truth.
    func presentationNode(
        for node: StoryNode,
        dispatch: StoryCommandDispatchResult
    ) -> StoryNode {
        guard normalized(node.assetId) == nil else { return node }
        let commandAssetID = dispatch.effects.lazy.compactMap { effect -> String? in
            switch effect {
            case .playAudio(let assetID), .recordAudio(let assetID):
                return assetID
            default:
                return nil
            }
        }.first
        guard let commandAssetID else { return node }

        return StoryNode(
            nodeId: node.nodeId,
            lineOrder: node.lineOrder,
            speaker: node.speaker,
            messageType: node.messageType,
            text: node.text,
            choiceId: node.choiceId,
            nextNodeId: node.nextNodeId,
            saveKey: node.saveKey,
            saveValue: node.saveValue,
            assetId: commandAssetID,
            minPhase: node.minPhase,
            maxPhase: node.maxPhase,
            speakerName: node.speakerName,
            typingDurationMs: node.typingDurationMs,
            background: node.background,
            portrait: node.portrait,
            cg: node.cg,
            screenMode: node.screenMode,
            uiVariant: node.uiVariant,
            command: node.command,
            commandArgs: node.commandArgs,
            notes: node.notes
        )
    }
}

private extension StoryPlayer {
    func resolveNext(
        after node: StoryNode,
        selectedChoice: StoryChoice?,
        phase: Int
    ) throws -> StoryNode? {
        guard let graph else { return nil }
        do {
            return try graph.nextVisibleNode(
                after: node,
                selectedChoice: selectedChoice,
                phase: phase
            )
        } catch let error as StoryScenarioGraphError {
            report(error.localizedDescription)
            return try graph.nextVisibleLineOrderNode(after: node, phase: phase)
        }
    }

    func firstPlayableNode(in graph: StoryScenarioGraph) throws -> StoryNode? {
        do {
            return try graph.firstVisibleNode(phase: currentPhase)
        } catch let error as StoryScenarioGraphError {
            report(error.localizedDescription)
            return graph.firstVisibleLineOrderNode(phase: currentPhase)
        }
    }

    func projectedPhase(applyingProfileKey key: String?, value: String?) -> Int {
        guard normalized(key) == StoryStateRepository.relationshipPhaseKey,
              let value,
              let phase = Int(value) else {
            return currentPhase
        }
        return phase
    }

    func appendVisibleChatNodeIfNeeded(_ node: StoryNode) {
        let isRenderableAction = node.uiVariant == .audioMessage
            || node.uiVariant == .recording
            || node.uiVariant == .imageMessage
        guard currentMode == .chat,
              node.messageType != .action || isRenderableAction,
              !visibleChatNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return
        }
        visibleChatNodes.append(node)
    }

    func resetPresentation(clearError: Bool) {
        currentNode = nil
        currentMode = initialMode
        visibleChatNodes = []
        backgroundAssetID = event?.background
        portraitAssetID = nil
        cgAssetID = nil
        availableChoices = []
        isTyping = false
        isModalPresented = false
        isCompleted = false
        callState = nil
        activeAudioAssetID = nil
        if clearError { recoverableError = nil }
    }

    func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func report(_ message: String) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        logger(message)
        guard let existing = recoverableError, !existing.isEmpty else {
            recoverableError = message
            return
        }
        let messages = existing.components(separatedBy: "\n")
        guard !messages.contains(message) else { return }
        recoverableError = (Array(messages.suffix(3)) + [message]).joined(separator: "\n")
    }

    func beginOperation() -> UInt64? {
        guard !isProcessing else { return nil }
        operationGeneration &+= 1
        isProcessing = true
        return operationGeneration
    }

    func beginReplacingOperation() -> UInt64 {
        operationGeneration &+= 1
        isProcessing = true
        return operationGeneration
    }

    func endOperation(_ token: UInt64) {
        if operationGeneration == token { isProcessing = false }
    }
}
