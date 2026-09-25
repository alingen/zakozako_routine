import Foundation
import Observation

typealias StoryPlayerSleep = (UInt64) async throws -> Void
typealias StoryPlayerLogger = (String) -> Void
typealias StoryPlayerNow = () -> Date

enum StoryAdvancePace: Equatable {
    case normal
    case fastForward
}

enum StoryPlaybackTiming {
    static let fastForwardMaximumCommandWaitMilliseconds: UInt64 = 60

    static func commandWaitMilliseconds(
        _ milliseconds: UInt64,
        pace: StoryAdvancePace
    ) -> UInt64 {
        switch pace {
        case .normal:
            return milliseconds
        case .fastForward:
            return min(milliseconds, fastForwardMaximumCommandWaitMilliseconds)
        }
    }
}

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
    private(set) var visibleLogNodes: [StoryNode] = []
    private(set) var backgroundAssetID: String?
    private(set) var portraitAssetID: String?
    private(set) var cgAssetID: String?
    private(set) var shouldDelayCurrentADVText = false
    private(set) var isHesitating = false
    private(set) var availableChoices: [StoryChoice] = []
    private(set) var isTyping = false
    private(set) var isModalPresented = false
    private(set) var isCompleted = false
    private(set) var recoverableError: String?
    private(set) var sceneTransition: StorySceneTransitionState?

    var isCurrentNodeTerminal: Bool {
        guard let graph,
              let node = currentNode,
              node.choiceId == nil,
              node.messageType != .choice else {
            return false
        }

        let nextPhase = projectedPhase(
            applyingProfileKey: node.saveKey,
            value: node.saveValue
        )
        do {
            return try graph.nextVisibleNode(after: node, phase: nextPhase) == nil
        } catch {
            return (try? graph.nextVisibleLineOrderNode(after: node, phase: nextPhase)) == nil
        }
    }

    /// Additional presentation facts retained for future renderers. Existing
    /// renderers can continue reading `currentNode.assetId` directly.
    private(set) var callState: StoryCallPresentationState?
    private(set) var activeAudioAssetID: String?
    private(set) var bgmPlaybackState: StoryBGMPlaybackState?
    private(set) var pendingSoundEffects: [StorySoundEffectPlayback] = []
    private(set) var loopingSoundEffects: [String: StorySoundEffectPlayback] = [:]

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
    @ObservationIgnored private let preloadSceneAssets: @MainActor ([String]) async -> Void
    @ObservationIgnored private let transitionFrameBarrier: @MainActor () async -> Void
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool
    @ObservationIgnored private let transitionUptime: () -> TimeInterval
    @ObservationIgnored private var assetPreparation: Task<Void, Never>?
    @ObservationIgnored private var preparedAssetIDs: [String] = []
    @ObservationIgnored private var assetsReady = false
    @ObservationIgnored private var assetPreparationGeneration: UInt64 = 0
    @ObservationIgnored private var coveredSince: TimeInterval = 0

    @ObservationIgnored private var checkpoint: StoryPlaybackCheckpoint?
    @ObservationIgnored private var currentPhase = 0
    @ObservationIgnored private var operationGeneration: UInt64 = 0
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var awaitsTextAfterClearBackground = false

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
        now: @escaping StoryPlayerNow = Date.init,
        preloadSceneAssets: @escaping @MainActor ([String]) async -> Void = { _ in },
        transitionFrameBarrier: @escaping @MainActor () async -> Void = {},
        reduceMotion: @escaping @MainActor () -> Bool = { false },
        transitionUptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
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
        self.preloadSceneAssets = preloadSceneAssets
        self.transitionFrameBarrier = transitionFrameBarrier
        self.reduceMotion = reduceMotion
        self.transitionUptime = transitionUptime

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
                // Opening an already-read event is a reread. Preserve its read
                // state and unlocked memories, but always begin playback from
                // the first node instead of returning to an old position.
                if event != nil {
                    checkpoint = try stateRepository.restartPlayback(
                        playbackKey: playbackKey,
                        scenarioId: scenario.scenarioId,
                        at: now()
                    )
                    self.checkpoint = checkpoint
                    resetPresentation(clearError: false)
                } else {
                    currentNode = nil
                    availableChoices = []
                    isCompleted = true
                    return
                }
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
    func advance(
        expectedNodeId: String? = nil,
        pace: StoryAdvancePace = .normal
    ) async {
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
                try await drive(
                    from: next,
                    firstNodeWasReplayed: false,
                    token: token,
                    skipsCommandWaits: pace == .fastForward
                )
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

    /// Records a renderer-controlled chat reveal without advancing playback.
    /// This keeps typing or unsent messages out of the event log.
    func markCurrentNodePresented(expectedNodeId: String? = nil) {
        guard expectedNodeId == nil || currentNode?.nodeId == expectedNodeId,
              let currentNode else {
            return
        }
        appendVisibleLogNodeIfNeeded(currentNode)
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

    /// Ends the current event without preserving a resumable position. Event
    /// completion/read state is retained; opening it again starts a reread at
    /// the first node via `start()`.
    @discardableResult
    func skip() async -> Bool {
        guard sceneTransition == nil else { return false }
        let token = beginReplacingOperation()
        isClosed = false
        defer { endOperation(token) }

        do {
            let checkpointToComplete = checkpoint ?? StoryPlaybackCheckpoint(
                playbackKey: playbackKey,
                scenarioId: scenario.scenarioId,
                updatedAt: now()
            )
            try complete(checkpoint: checkpointToComplete)
            return true
        } catch {
            guard operationGeneration == token else { return false }
            report(error.localizedDescription)
            return false
        }
    }

    /// Invalidates an in-flight wait. Entry checkpoints are already durable,
    /// so closing requires no additional write.
    func close() {
        operationGeneration &+= 1
        isProcessing = false
        isClosed = true
        isHesitating = false
        isModalPresented = false
        availableChoices = []
        cancelSceneTransition()
    }

    func consumePendingSoundEffects() -> [StorySoundEffectPlayback] {
        let effects = pendingSoundEffects
        pendingSoundEffects = []
        return effects
    }
}

private extension StoryPlayer {
    func drive(
        from firstNode: StoryNode,
        firstNodeWasReplayed: Bool,
        token: UInt64,
        skipsCommandWaits: Bool = false
    ) async throws {
        defer {
            if operationGeneration == token {
                sceneTransition = nil
                isHesitating = false
            }
        }
        try await driveNodes(
            from: firstNode,
            firstNodeWasReplayed: firstNodeWasReplayed,
            token: token,
            skipsCommandWaits: skipsCommandWaits
        )
        guard operationGeneration == token, !isClosed else { return }
        if let transition = sceneTransition {
            // The new background, portrait, text and choices are all committed
            // while fully covered. Wait for their rendered frame before opening.
            await transitionFrameBarrier()
            try validateTransitionOperation(token)
            let remaining = transition.configuration.minimumHold - (transitionUptime() - coveredSince)
            if remaining > 0 { try await sleep(UInt64(ceil(remaining * 1_000))) }
            try validateTransitionOperation(token)
            sceneTransition = StorySceneTransitionState(
                configuration: transition.configuration, phase: .revealing,
                startedAt: transitionUptime(), reduceMotion: transition.reduceMotion
            )
            try await sleep(UInt64((transition.configuration.effectiveRevealDuration(
                reduceMotion: transition.reduceMotion
            ) * 1_000).rounded()))
            try validateTransitionOperation(token)
            sceneTransition = nil
        }
        prefetchNextScene()
    }

    func driveNodes(
        from firstNode: StoryNode,
        firstNodeWasReplayed: Bool,
        token: UInt64,
        skipsCommandWaits: Bool
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
            if !replayed, currentNode != nil, currentMode == .adv,
               sceneTransition == nil,
               normalized(node.command)?.lowercased() == "scene_change",
               let configuration = StorySceneTransitionConfiguration(arguments: node.commandArgs) {
                try await coverScene(configuration: configuration, startingAt: node, token: token)
            }
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
                isHesitating = false
            } else {
                isModalPresented = false
                activeAudioAssetID = nil
                let displayedNode = presentationNode(for: node, dispatch: dispatch)
                currentNode = displayedNode
                availableChoices = []
                isHesitating = !pausesForUser && dispatch.effects.contains {
                    if case .portraitHesitation = $0 { return true }
                    return false
                }

                let encounteredCGs = applyPresentation(
                    node: node,
                    dispatch: dispatch,
                    allowTransientEffects: true
                )
                for effect in dispatch.effects {
                    if case .playSoundEffect(let sound) = effect, !sound.loop {
                        pendingSoundEffects.append(sound)
                    }
                }
                appendVisibleChatNodeIfNeeded(displayedNode)
                if currentMode != .chat {
                    appendVisibleLogNodeIfNeeded(displayedNode)
                }
                availableChoices = resolvedChoices
                try persistEntry(node: node, encounteredCGs: encounteredCGs)
            }

            if let diagnostic = dispatch.diagnostic { report(diagnostic) }
            if pausesForUser { return }

            if !replayed, let waitMilliseconds = waitMilliseconds(in: dispatch) {
                let effectiveWait = StoryPlaybackTiming.commandWaitMilliseconds(
                    waitMilliseconds,
                    pace: skipsCommandWaits ? .fastForward : .normal
                )
                try await sleep(effectiveWait)
                guard operationGeneration == token, !isClosed else { return }
                isHesitating = false
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

        // Chat messages become part of the log only after they have actually
        // been sent/revealed and consumed. ADV/call nodes are already added on
        // entry, and the helper de-duplicates them.
        appendVisibleLogNodeIfNeeded(node)

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
            appendSelectedChatReplyIfNeeded(history, after: node)
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
        loopingSoundEffects = [:]
        shouldDelayCurrentADVText = false
        isHesitating = false
        awaitsTextAfterClearBackground = false
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
            let isReplayedCurrentNode = index == replayedCurrentIndex
            if !isReplayedCurrentNode || currentMode != .chat {
                appendVisibleLogNodeIfNeeded(displayedNode)
            }
            if !isReplayedCurrentNode {
                for selection in checkpoint.choiceHistory where selection.nodeId == nodeId {
                    appendSelectedChatReplyIfNeeded(selection, after: displayedNode)
                }
            }
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
    /// command_args may set a mode before the row-level mode is resolved.
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
            awaitsTextAfterClearBackground = false
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
                awaitsTextAfterClearBackground = false
            case .clearBackground:
                backgroundAssetID = nil
                awaitsTextAfterClearBackground = true
            case .setPortrait(let assetID):
                portraitAssetID = assetID
            case .clearPortrait:
                portraitAssetID = nil
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
                // A scripted pause already separates the blackout from the next line.
                // Do not add the renderer's implicit 300 ms delay on top of it.
                awaitsTextAfterClearBackground = false
                break
            case .portraitHesitation:
                break
            case .setCallState(let state):
                callState = state
            case .playAudio(let assetID), .recordAudio(let assetID):
                if allowTransientEffects { activeAudioAssetID = assetID }
            case .playBGM(let state):
                bgmPlaybackState = state
            case .stopBGM:
                bgmPlaybackState = nil
            case .playSoundEffect(let sound):
                if sound.loop {
                    loopingSoundEffects[sound.assetID] = sound
                }
            case .stopSoundEffect(let assetID):
                loopingSoundEffects.removeValue(forKey: assetID)
            }
        }

        if let mode = node.screenMode {
            currentMode = StoryScreenModeTransitionPolicy.resolveRowMode(
                mode,
                currentMode: currentMode,
                scenarioType: scenario.scenarioType,
                hasExplicitTransition: normalized(node.command)?.lowercased() == "scene_change"
            )
        }
        shouldDelayCurrentADVText = node.messageType == .text
            && currentMode == .adv
            && backgroundAssetID == nil
            && portraitAssetID == nil
            && awaitsTextAfterClearBackground
        if node.messageType == .text {
            awaitsTextAfterClearBackground = false
        }
        return encounteredCGs
    }

    func choices(for node: StoryNode) throws -> [StoryChoice] {
        guard let choiceId = normalized(node.choiceId) else { return [] }
        let candidates = contentRepository.choices(id: choiceId)
        guard !candidates.isEmpty else {
            report("choice group \(choiceId) が見つかりません")
            return []
        }
        return candidates
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

        // A hesitation command is an automatic visual beat, not a dialogue
        // step. Keep that behavior even if a row has an unexpected UI variant.
        if dispatch.effects.contains(where: {
            if case .portraitHesitation = $0 { return true }
            return false
        }) {
            return false
        }

        // A labelled transition is visible content. An empty transition is a
        // state-only command (background/mode change), so apply it without
        // exposing a blank "System" dialogue step to the reader.
        if node.uiVariant == .sceneTransition {
            return normalized(node.text) != nil
        }

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
            if case .portraitHesitation(let milliseconds) = effect { return milliseconds }
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

enum StoryScreenModeTransitionPolicy {
    static func resolveRowMode(
        _ requestedMode: StoryScreenMode,
        currentMode: StoryScreenMode,
        scenarioType: StoryScenarioType,
        hasExplicitTransition: Bool
    ) -> StoryScreenMode {
        guard requestedMode == .chat,
              currentMode != .chat,
              requiresExplicitChatEntry(scenarioType),
              !hasExplicitTransition else {
            return requestedMode
        }

        // Prologue, middle, and large events use scene_change to enter a chat section.
        // Its dispatch effect may already have changed currentMode before
        // this resolver runs. A lone row-level `chat` value must not flash
        // the chat UI for a single quoted line.
        return currentMode
    }

    private static func requiresExplicitChatEntry(
        _ scenarioType: StoryScenarioType
    ) -> Bool {
        switch scenarioType {
        case .prologue, .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
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
        // A choice row may contain Rio's question, but it is not a sent
        // protagonist reply. The selected label is appended only after saving.
        let isUnsentChoice = scenario.scenarioType == .daily
            && (node.choiceId != nil || node.messageType == .choice)
            && (node.isPlayerSpeaker || normalized(node.text) == nil)
        guard currentMode == .chat,
              !isUnsentChoice,
              node.messageType != .action || isRenderableAction,
              !visibleChatNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return
        }
        visibleChatNodes.append(node)
    }

    func appendSelectedChatReplyIfNeeded(
        _ selection: StoryChoiceHistoryEntry,
        after node: StoryNode
    ) {
        guard scenario.scenarioType == .daily,
              currentMode == .chat,
              normalized(selection.label) != nil else { return }
        // Presentation-only node: navigation and persistence keep using the
        // source choice row and its existing durable choice history.
        let reply = StoryNode(
            nodeId: "story-choice-reply:\(selection.id)",
            lineOrder: node.lineOrder,
            speaker: "user",
            messageType: .text,
            text: selection.label,
            screenMode: .chat,
            uiVariant: .dialogue
        )
        appendVisibleChatNodeIfNeeded(reply)
    }

    func appendVisibleLogNodeIfNeeded(_ node: StoryNode) {
        switch scenario.scenarioType {
        case .prologue, .middleEvent, .largeEvent:
            break
        case .daily, .smallEvent, .unknown:
            return
        }
        let text = normalized(node.text)
            ?? normalized(node.commandArgs?["text"]?.stringValue)
        guard text != nil,
              node.uiVariant != .titleCard,
              node.uiVariant != .typing,
              !visibleLogNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return
        }
        visibleLogNodes.append(node)
    }

    func resetPresentation(clearError: Bool) {
        cancelSceneTransition()
        currentNode = nil
        currentMode = initialMode
        visibleChatNodes = []
        visibleLogNodes = []
        backgroundAssetID = event?.background
        portraitAssetID = nil
        cgAssetID = nil
        shouldDelayCurrentADVText = false
        isHesitating = false
        awaitsTextAfterClearBackground = false
        availableChoices = []
        isTyping = false
        isModalPresented = false
        isCompleted = false
        callState = nil
        activeAudioAssetID = nil
        bgmPlaybackState = nil
        pendingSoundEffects = []
        loopingSoundEffects = [:]
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

    func coverScene(
        configuration: StorySceneTransitionConfiguration,
        startingAt node: StoryNode,
        token: UInt64
    ) async throws {
        prepareAssets(sceneAssetIDs(startingAt: node))
        let reduced = reduceMotion()
        if configuration.type == .colorSlide {
            pendingSoundEffects.append(
                StorySoundEffectPlayback(assetID: "se_color_slide", volume: 1)
            )
        }
        sceneTransition = StorySceneTransitionState(
            configuration: configuration, phase: .covering,
            startedAt: transitionUptime(), reduceMotion: reduced
        )
        try await sleep(UInt64((configuration.effectiveCoverDuration(reduceMotion: reduced) * 1_000).rounded()))
        try validateTransitionOperation(token)
        coveredSince = transitionUptime()
        sceneTransition = StorySceneTransitionState(
            configuration: configuration, phase: .covered,
            startedAt: coveredSince, reduceMotion: reduced, isWaitingForAssets: !assetsReady
        )
        // Two display-link ticks in the SwiftUI host acknowledge a fully opaque
        // rendered frame. Do not exchange scene data merely on a timer callback.
        await transitionFrameBarrier()
        try validateTransitionOperation(token)
        await assetPreparation?.value
        try validateTransitionOperation(token)
        sceneTransition?.isWaitingForAssets = false
    }

    func validateTransitionOperation(_ token: UInt64) throws {
        guard operationGeneration == token, !isClosed, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    func prepareAssets(_ ids: [String]) {
        guard ids != preparedAssetIDs || assetPreparation == nil else { return }
        assetPreparation?.cancel()
        assetPreparationGeneration &+= 1
        let generation = assetPreparationGeneration
        preparedAssetIDs = ids
        assetsReady = false
        let load = preloadSceneAssets
        assetPreparation = Task { [weak self] in
            await load(ids)
            guard !Task.isCancelled, let self, self.assetPreparationGeneration == generation else { return }
            self.assetsReady = true
        }
    }

    func prefetchNextScene() {
        guard let graph, let currentNode, !isCompleted,
              let next = try? graph.nextVisibleNode(after: currentNode, phase: currentPhase) else { return }
        prepareAssets(sceneAssetIDs(startingAt: next))
    }

    /// Look ahead only through automatic commands to the next visible node.
    /// This is read-only: no checkpoints, flags, choices or rewards are changed.
    func sceneAssetIDs(startingAt first: StoryNode) -> [String] {
        guard let graph else { return [] }
        var ids = Set<String>()
        var visited = Set<String>()
        var cursor: StoryNode? = first
        while let node = cursor, visited.insert(node.nodeId).inserted {
            for value in [node.background, node.portrait, node.cg] {
                if let value = normalized(value) { ids.insert(value) }
            }
            let dispatch = commandDispatcher.dispatch(node: node)
            for effect in dispatch.effects {
                switch effect {
                case .setBackground(let id), .setPortrait(let id), .showCG(let id): ids.insert(id)
                default: break
                }
            }
            if node.messageType == .image, let id = node.assetId { ids.insert(id) }
            if shouldPauseForUser(on: node, dispatch: dispatch) { break }
            cursor = try? graph.nextVisibleNode(after: node, phase: currentPhase)
        }
        return ids.sorted()
    }

    func cancelSceneTransition() {
        sceneTransition = nil
        assetPreparation?.cancel()
        assetPreparation = nil
        assetPreparationGeneration &+= 1
        preparedAssetIDs = []
        assetsReady = false
    }
}
