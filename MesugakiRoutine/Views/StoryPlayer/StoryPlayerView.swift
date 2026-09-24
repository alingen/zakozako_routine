import SwiftUI

/// Story Playerエンジンの状態を、描画層へ渡すための読み取り専用境界。
/// Core側のObservableなplayerは、このprotocolへ直接準拠するかSnapshotへ変換できる。
protocol StoryPlayerViewInput {
    var title: String { get }
    var scenarioType: StoryScenarioType { get }
    var currentNode: StoryNode? { get }
    var currentMode: StoryScreenMode { get }
    var visibleChatNodes: [StoryNode] { get }
    var visibleLogNodes: [StoryNode] { get }
    var backgroundAssetID: String? { get }
    var portraitAssetID: String? { get }
    var cgAssetID: String? { get }
    var shouldDelayCurrentADVText: Bool { get }
    var availableChoices: [StoryChoice] { get }
    var isTyping: Bool { get }
    var isModalPresented: Bool { get }
    var isCompleted: Bool { get }
    var isCurrentNodeTerminal: Bool { get }
    var recoverableError: String? { get }
}

/// Core player未接続時やPreview、テストでも使える値型adapter。
struct StoryPlayerViewSnapshot: StoryPlayerViewInput {
    let title: String
    let scenarioType: StoryScenarioType
    let currentNode: StoryNode?
    let currentMode: StoryScreenMode
    let visibleChatNodes: [StoryNode]
    let visibleLogNodes: [StoryNode]
    let backgroundAssetID: String?
    let portraitAssetID: String?
    let cgAssetID: String?
    let shouldDelayCurrentADVText: Bool
    let availableChoices: [StoryChoice]
    let isTyping: Bool
    let isModalPresented: Bool
    let isCompleted: Bool
    let isCurrentNodeTerminal: Bool
    let recoverableError: String?

    init(
        title: String,
        scenarioType: StoryScenarioType,
        currentNode: StoryNode?,
        currentMode: StoryScreenMode = .adv,
        visibleChatNodes: [StoryNode] = [],
        visibleLogNodes: [StoryNode] = [],
        backgroundAssetID: String? = nil,
        portraitAssetID: String? = nil,
        cgAssetID: String? = nil,
        shouldDelayCurrentADVText: Bool = false,
        availableChoices: [StoryChoice] = [],
        isTyping: Bool = false,
        isModalPresented: Bool = false,
        isCompleted: Bool = false,
        isCurrentNodeTerminal: Bool = false,
        recoverableError: String? = nil
    ) {
        self.title = title
        self.scenarioType = scenarioType
        self.currentNode = currentNode
        self.currentMode = currentMode
        self.visibleChatNodes = visibleChatNodes
        self.visibleLogNodes = visibleLogNodes
        self.backgroundAssetID = backgroundAssetID
        self.portraitAssetID = portraitAssetID
        self.cgAssetID = cgAssetID
        self.shouldDelayCurrentADVText = shouldDelayCurrentADVText
        self.availableChoices = availableChoices
        self.isTyping = isTyping
        self.isModalPresented = isModalPresented
        self.isCompleted = isCompleted
        self.isCurrentNodeTerminal = isCurrentNodeTerminal
        self.recoverableError = recoverableError
    }
}

/// fullScreenCoverでの表示を前提とするStory Playerの統合画面。
/// シナリオ進行や永続化は行わず、すべてcallbackを通じてCoreへ委譲する。
struct StoryPlayerView: View {
    let input: any StoryPlayerViewInput
    var advOpeningRevealPhase: ADVOpeningRevealPhase = .text
    var allowsSkip = true
    var isSceneTransitionActive = false
    let onAdvance: (StoryAdvancePace) -> Void
    let onChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void
    let onPresentNode: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void
    var onTextWindowTap: () -> Void = {}

    @State private var isShowingLog = false
    @State private var advPlaybackMode: ADVPlaybackMode = .manual

    private var isAutomaticallyReturningCompletedEvent: Bool {
        input.isCompleted
            && StoryCompletionPresentationPolicy.returnsToMenuAutomatically(
                after: input.scenarioType
            )
    }

    private var usesSkipOnlyDismissal: Bool {
        switch input.scenarioType {
        case .prologue, .smallEvent, .middleEvent, .largeEvent:
            return true
        case .daily, .unknown:
            return false
        }
    }

    var body: some View {
        ZStack {
            playerContent
                .ignoresSafeArea(edges: ignoredSafeAreaEdges)
                .allowsHitTesting(!isShowingLog)

            if !isAutomaticallyReturningCompletedEvent, !isShowingLog {
                VStack(spacing: 10) {
                    topBar

                    if let error = input.recoverableError, !error.isEmpty {
                        recoverableErrorBanner(error)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            if isShowingLog {
                StoryLogView(
                    title: input.title,
                    nodes: input.visibleLogNodes,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isShowingLog = false
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .onChange(of: input.currentMode.rawValue) { _, mode in
            if mode != StoryScreenMode.adv.rawValue {
                stopADVPlaybackModes()
            }
        }
        .onChange(of: input.availableChoices.count) { _, choiceCount in
            if choiceCount > 0, advPlaybackMode == .fastForward {
                advPlaybackMode = .manual
            }
        }
        .onChange(of: input.isModalPresented) { _, isPresented in
            if isPresented, advPlaybackMode == .fastForward {
                advPlaybackMode = .manual
            }
        }
        .onChange(of: input.recoverableError ?? "") { _, message in
            if !message.isEmpty {
                stopADVPlaybackModes()
            }
        }
    }

    private var ignoredSafeAreaEdges: Edge.Set {
        switch input.currentMode {
        case .adv:
            // 背景はrenderer内で全面表示し、下部操作バーだけhome indicatorを避ける。
            return [.horizontal, .top]
        case .chat:
            return [.horizontal, .bottom]
        case .call, .unknown:
            return .all
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        if input.isCompleted {
            switch input.scenarioType {
            case .daily, .smallEvent:
                ChatStoryCompletionView(
                    visibleNodes: input.visibleChatNodes,
                    scenarioType: input.scenarioType,
                    onClose: onClose
                )
            case .prologue, .middleEvent, .largeEvent:
                Color.black.ignoresSafeArea()
            case .unknown:
                completionView
            }
        } else if let node = input.currentNode {
            switch input.currentMode {
            case .adv:
                ADVStoryRenderer(
                    node: node,
                    scenarioType: input.scenarioType,
                    backgroundAssetID: input.backgroundAssetID,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isModalPresented: input.isModalPresented,
                    openingRevealPhase: advOpeningRevealPhase,
                    delaysTextAfterBlackout: input.shouldDelayCurrentADVText,
                    playbackMode: advPlaybackMode,
                    isPlaybackPaused: isShowingLog
                        || isSceneTransitionActive
                        || !advOpeningRevealPhase.startsTextReveal,
                    isAutomationAvailable: input.recoverableError?.isEmpty != false,
                    isLogAvailable: StoryLogPresentationPolicy.isAvailable(
                        for: input.scenarioType
                    ),
                    allowsSkip: allowsSkip,
                    onAdvance: onAdvance,
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal,
                    onTextWindowTap: onTextWindowTap,
                    onSkip: {
                        stopADVPlaybackModes()
                        onSkip()
                    },
                    onClose: {
                        stopADVPlaybackModes()
                        onClose()
                    },
                    onShowLog: showLog,
                    onToggleAuto: toggleADVAuto,
                    onToggleFastForward: toggleADVFastForward
                )
            case .chat:
                ChatStoryRenderer(
                    node: node,
                    scenarioType: input.scenarioType,
                    isTerminalNode: input.isCurrentNodeTerminal,
                    visibleNodes: input.visibleChatNodes,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isTyping: input.isTyping,
                    isModalPresented: input.isModalPresented,
                    onAdvance: { onAdvance(.normal) },
                    onPresentNode: onPresentNode,
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal,
                    onTextWindowTap: onTextWindowTap
                )
            case .call:
                CallStoryRenderer(
                    node: node,
                    backgroundAssetID: input.backgroundAssetID,
                    portraitAssetID: input.portraitAssetID,
                    cgAssetID: input.cgAssetID,
                    choices: input.availableChoices,
                    isModalPresented: input.isModalPresented,
                    onAdvance: { onAdvance(.normal) },
                    onSelectChoice: onChoice,
                    onDismissModal: onDismissModal
                )
            case .unknown(let rawValue):
                unknownModeView(node: node, modeName: rawValue)
            }
        } else {
            unavailableStateView
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !usesSkipOnlyDismissal || !allowsSkip {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(AppColor.text)
                .accessibilityLabel("ストーリーを閉じる")
            }

            Text(input.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if input.currentMode != .adv {
                Menu {
                    if StoryLogPresentationPolicy.isAvailable(for: input.scenarioType) {
                        Button {
                            showLog()
                        } label: {
                            Label("ログ", systemImage: "list.bullet.rectangle")
                        }
                    }
                    if usesSkipOnlyDismissal, allowsSkip, !input.isCompleted {
                        Button(action: onSkip) {
                            Label("スキップ", systemImage: "forward.end.fill")
                        }
                    } else {
                        Button(action: onClose) {
                            Label("閉じる", systemImage: "xmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(AppColor.text)
                .accessibilityLabel("ストーリーメニュー")
            }
        }
    }

    private func showLog() {
        if advPlaybackMode == .fastForward {
            advPlaybackMode = .manual
        }
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingLog = true
        }
    }

    private func toggleADVAuto() {
        advPlaybackMode = advPlaybackMode == .auto ? .manual : .auto
    }

    private func toggleADVFastForward() {
        advPlaybackMode = advPlaybackMode == .fastForward ? .manual : .fastForward
    }

    private func stopADVPlaybackModes() {
        advPlaybackMode = .manual
    }

    private func recoverableErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(AppColor.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.warning.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("注意。\(message)")
    }

    private var completionView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(AppColor.primary)
                .frame(width: 112, height: 112)
                .background(AppColor.primarySoft, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("読了")
                    .font(.title.bold())
                    .foregroundStyle(AppColor.text)
                Text(input.title)
                    .font(.headline)
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("閉じる", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .background(AppColor.background)
        .accessibilityElement(children: .contain)
    }

    private func unknownModeView(node: StoryNode, modeName: String) -> some View {
        ZStack(alignment: .top) {
            ADVStoryRenderer(
                node: node,
                scenarioType: input.scenarioType,
                backgroundAssetID: input.backgroundAssetID,
                portraitAssetID: input.portraitAssetID,
                cgAssetID: input.cgAssetID,
                choices: input.availableChoices,
                isModalPresented: input.isModalPresented,
                showsPlaybackControls: false,
                onAdvance: onAdvance,
                onSelectChoice: onChoice,
                onDismissModal: onDismissModal,
                onTextWindowTap: onTextWindowTap
            )

            Text("未対応の画面モード: \(modeName)")
                .font(.caption.monospaced())
                .foregroundStyle(AppColor.warning)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColor.surface.opacity(0.96), in: Capsule())
                .padding(.top, 58)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }

    private var unavailableStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(AppColor.muted)
            Text("表示できるシーンがありません")
                .font(.headline)
                .foregroundStyle(AppColor.text)
            if let error = input.recoverableError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
            }
            Button("閉じる", action: onClose)
            .buttonStyle(.bordered)
            .tint(AppColor.primary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }
}

private struct StoryLogView: View {
    let title: String
    let nodes: [StoryNode]
    let onClose: () -> Void

    private let bottomAnchorID = "story-log-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ログ")
                        .font(.title2.bold())
                        .foregroundStyle(AppColor.text)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                        .background(AppColor.surface, in: Circle())
                        .overlay(Circle().stroke(AppColor.border))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.text)
                .accessibilityLabel("ログを閉じる")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if nodes.isEmpty {
                ContentUnavailableView(
                    "ログはまだありません",
                    systemImage: "text.bubble",
                    description: Text("表示されたセリフがここに記録されます")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(nodes) { node in
                                StoryLogRow(node: node)

                                if node.id != nodes.last?.id {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                        }
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }
}

private struct StoryLogRow: View {
    let node: StoryNode

    private var normalizedSpeaker: String {
        node.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isProtagonist: Bool {
        ["user", "player", "protagonist"].contains(normalizedSpeaker)
            || node.storyDisplaySpeakerName == "主人公"
    }

    private var displaySpeakerName: String? {
        if normalizedSpeaker == "narrator" || normalizedSpeaker == "system" {
            return nil
        }
        if isProtagonist {
            let nickname = AppSettingsStore.userName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return nickname.isEmpty ? "主人公" : nickname
        }
        if let speakerName = node.storyDisplaySpeakerName {
            switch speakerName.lowercased() {
            case "system", "地の文": return nil
            default: return speakerName
            }
        }
        switch normalizedSpeaker {
        case "rio", "character": return "莉央"
        default: return node.speaker.isEmpty ? nil : node.speaker
        }
    }

    private var isNarration: Bool {
        displaySpeakerName == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let displaySpeakerName {
                Text(displaySpeakerName)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.primary)
            }

            Text(node.storyDisplayText)
                .font(.body)
                .foregroundStyle(isNarration ? AppColor.muted : AppColor.text)
                .italic(isNarration)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
