import SwiftUI

/// チャット表示専用のrenderer。表示済みnode列を受け取り、進行処理はcallbackへ返す。
struct ChatStoryRenderer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: StoryNode
    let scenarioType: StoryScenarioType
    var isTerminalNode = false
    var visibleNodes: [StoryNode] = []
    var portraitAssetID: String?
    var cgAssetID: String?
    var choices: [StoryChoice] = []
    var isTyping = false
    var isWaitingForChatExit = false
    var isModalPresented = false
    let onAdvance: () -> Void
    let onPresentNode: () -> Void
    let onSelectChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void
    var onTextWindowTap: () -> Void = {}

    @State private var typingStartedRioNodeID: String?
    @State private var revealedRioNodeID: String?
    @State private var revealedSystemNodeID: String?

    private var effectivePortrait: String? { portraitAssetID ?? node.portrait }
    private var effectiveCG: String? { cgAssetID ?? node.cg }
    private var canAdvance: Bool { choices.isEmpty && !isModalPresented && !isTyping && !isWaitingForChatExit }
    private var usesEventChatFlow: Bool {
        switch scenarioType {
        case .prologue, .smallEvent, .middleEvent, .largeEvent:
            return true
        case .daily, .unknown:
            return false
        }
    }
    private var waitsForTerminalAdvance: Bool {
        isTerminalNode
            && StoryCompletionPresentationPolicy.returnsToMenuAutomatically(
                after: scenarioType
            )
    }
    private var shouldAutomaticallyPresentNode: Bool {
        guard canAdvance, !usesFullscreenNarration else { return false }
        if usesEventChatFlow {
            return !isWaitingToSendPlayerMessage
        }
        return node.isRioSpeaker && node.messageType == .text
    }
    var shouldAutoAdvance: Bool {
        shouldAutomaticallyPresentNode && !waitsForTerminalAdvance
            && !requiresManualNarrationAdvance
    }
    private var requiresManualNarrationAdvance: Bool {
        EventChatSystemPresentationPolicy.requiresManualAdvance(node: node, scenarioType: scenarioType)
    }
    private var usesFullscreenNarration: Bool {
        EventChatSystemPresentationPolicy.usesFullscreenNarration(node: node)
    }
    private var isWaitingToSendPlayerMessage: Bool {
        ChatStoryPresentationPolicy.isUnsentPlayerMessage(node: node, canAdvance: canAdvance)
    }
    private var isWaitingForRioMessage: Bool {
        shouldAutomaticallyPresentNode
            && node.isRioSpeaker
            && node.messageType == .text
            && revealedRioNodeID != node.nodeId
    }
    private var isShowingRioTyping: Bool {
        isWaitingForRioMessage && typingStartedRioNodeID == node.nodeId
    }
    private var isWaitingForSystemMessage: Bool {
        shouldAutomaticallyPresentNode
            && usesEventChatFlow
            && EventChatSystemPresentationPolicy.usesInlineNarration(node: node)
            && node.messageType == .text
            && revealedSystemNodeID != node.nodeId
    }

    private var isInitialEventPlayerMessage: Bool {
        guard usesEventChatFlow, isWaitingToSendPlayerMessage else {
            return false
        }
        return !visibleNodes.contains {
            $0.nodeId != node.nodeId && ($0.isPlayerSpeaker || $0.isRioSpeaker)
        }
    }

    private var manualAdvanceLabel: String {
        ChatStoryPresentationPolicy.manualAdvanceLabel(
            node: node,
            scenarioType: scenarioType,
            isInitialEventPlayerMessage: isInitialEventPlayerMessage,
            isTerminalNode: isTerminalNode
        )
    }

    private var manualAdvanceSymbol: String {
        if isCloseButton { return "xmark" }
        return node.isPlayerSpeaker ? "paperplane.fill" : "chevron.right"
    }

    private var isCloseButton: Bool {
        waitsForTerminalAdvance && !node.isPlayerSpeaker
    }

    private let rioResponsePauseNanoseconds: UInt64 = 350_000_000
    private let defaultRioTypingDurationMilliseconds = 600
    private let automaticContentDelayNanoseconds: UInt64 = 900_000_000

    private var rioTypingDelayNanoseconds: UInt64 {
        let configuredMilliseconds = node.typingDurationMs ?? defaultRioTypingDurationMilliseconds
        let milliseconds = min(30_000, max(0, configuredMilliseconds))
        return UInt64(milliseconds) * 1_000_000
    }

    private var automaticAdvanceDelayNanoseconds: UInt64 {
        let characterCount = node.text?.count ?? 0
        let milliseconds = min(3_200, max(1_100, 900 + characterCount * 55))
        return UInt64(milliseconds) * 1_000_000
    }

    private var renderedNodes: [StoryNode] {
        let sentNodes = visibleNodes.filter {
            !ChatStoryPresentationPolicy.isChoicePlaceholder(node: $0, scenarioType: scenarioType)
                && ((!isWaitingToSendPlayerMessage
                && !isWaitingForRioMessage
                && !isWaitingForSystemMessage)
                || $0.nodeId != node.nodeId)
        }
        guard !ChatStoryPresentationPolicy.isChoicePlaceholder(node: node, scenarioType: scenarioType),
              !isWaitingToSendPlayerMessage,
              !isWaitingForRioMessage,
              !isWaitingForSystemMessage,
              !sentNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return sentNodes
        }
        return sentNodes + [node]
    }

    private var chatHistoryNodes: [StoryNode] {
        renderedNodes.filter {
            !EventChatSystemPresentationPolicy.omitsFromChatHistory(
                node: $0,
                scenarioType: scenarioType
            )
        }
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatHistoryNodes) { messageNode in
                                StoryChatBubble(
                                    node: messageNode,
                                    scenarioType: scenarioType,
                                    portraitAssetID: messageNode.nodeId == node.nodeId
                                        ? effectivePortrait
                                        : messageNode.portrait,
                                    cgAssetID: messageNode.nodeId == node.nodeId
                                        ? effectiveCG
                                        : messageNode.cg
                                )
                                    .id(messageNode.nodeId)
                            }

                            if isShowingRioTyping {
                                HStack(alignment: .bottom, spacing: 8) {
                                    rioAvatar
                                    RioTypingIndicator()
                                    Spacer(minLength: 52)
                                }
                                .id("story-chat-rio-typing")
                            } else if isTyping {
                                HStack {
                                    StoryTypingView(node: node)
                                    Spacer(minLength: 52)
                                }
                                .id("story-chat-typing")
                            }

                            Color.clear
                                .frame(height: 16)
                                .id("story-chat-bottom-spacing")
                                .accessibilityHidden(true)
                        }
                        .padding(16)
                    }
                    .onAppear { scrollToLatest(proxy) }
                    .onChange(of: chatHistoryNodes.count) { _, _ in scrollToLatest(proxy) }
                    .onChange(of: isTyping) { _, _ in scrollToLatest(proxy) }
                    .onChange(of: isShowingRioTyping) { _, _ in scrollToLatest(proxy) }
                }
                .padding(.top, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                actionArea
                    .opacity(usesFullscreenNarration ? 0 : 1)
                    .allowsHitTesting(!usesFullscreenNarration)
                    .accessibilityHidden(usesFullscreenNarration)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: usesFullscreenNarration)
            }
            .allowsHitTesting(!usesFullscreenNarration)
            .accessibilityHidden(usesFullscreenNarration)

            if usesFullscreenNarration {
                FullscreenChatNarrationView(
                    node: node,
                    canAdvance: canAdvance,
                    onPresentNode: onPresentNode,
                    onAdvance: {
                        // このモードは最後の行もタップで終了する。別の「閉じる」は挟まない。
                        onTextWindowTap()
                        onAdvance()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if isModalPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                StoryModalView(node: node, onDismiss: onDismissModal)
                    .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: usesFullscreenNarration)
        .task(id: node.nodeId) {
            guard shouldAutomaticallyPresentNode else { return }
            do {
                if node.isRioSpeaker && node.messageType == .text {
                    try await Task<Never, Never>.sleep(
                        nanoseconds: rioResponsePauseNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        typingStartedRioNodeID = node.nodeId
                    }
                    try await Task<Never, Never>.sleep(
                        nanoseconds: rioTypingDelayNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        revealedRioNodeID = node.nodeId
                    }
                    onPresentNode()
                    try await Task<Never, Never>.sleep(
                        nanoseconds: automaticAdvanceDelayNanoseconds
                    )
                } else if isWaitingForSystemMessage {
                    try await Task<Never, Never>.sleep(
                        nanoseconds: automaticContentDelayNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        revealedSystemNodeID = node.nodeId
                    }
                    onPresentNode()
                } else {
                    onPresentNode()
                    // 中大イベントの地の文は下部ボタンで進める。本文自体はタップ不可。
                    guard !requiresManualNarrationAdvance else { return }
                    try await Task<Never, Never>.sleep(
                        nanoseconds: automaticContentDelayNanoseconds
                    )
                }
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if shouldAutoAdvance {
                onAdvance()
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if ChatStoryPresentationPolicy.usesFixedActionArea(for: scenarioType) {
            fixedChatActionArea
        } else if !choices.isEmpty {
            Divider()
            StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                .padding(16)
                .background(AppColor.background.opacity(0.96))
        } else if canAdvance && !node.isRioSpeaker {
            manualAdvanceArea
        }
    }

    private var fixedChatActionArea: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if !choices.isEmpty {
                    StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                } else if canAdvance,
                          !shouldAutoAdvance,
                          !isWaitingForRioMessage,
                          !isWaitingForSystemMessage {
                    advanceControl
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: usesEventChatFlow ? 81 : nil)
        .frame(minHeight: 81)
        .safeAreaPadding(.bottom, 8)
        .background(AppColor.background)
    }

    private var manualAdvanceArea: some View {
        VStack(spacing: 0) {
            Divider()
            advanceControl
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 81)
        .safeAreaPadding(.bottom, 8)
        .background(AppColor.background)
    }

    @ViewBuilder
    private var advanceControl: some View {
        if ChatStoryPresentationPolicy.usesPrefilledComposer(node: node, scenarioType: scenarioType) {
            prefilledComposer
        } else {
            manualAdvanceButton
        }
    }

    /// 主人公の発言は「入力済みの入力欄＋送信ボタン」で見せ、選択肢や「次へ」と区別する。
    /// 入力欄を含む全体をタップ範囲にする。
    private var prefilledComposer: some View {
        Button {
            onPresentNode()
            onAdvance()
        } label: {
            HStack(spacing: 10) {
                Text(node.storyDisplayText)
                    .font(.body)
                    .foregroundStyle(AppColor.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(minHeight: 48)
                    .background(
                        AppColor.surface,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppColor.border)
                    }

                Image(systemName: "paperplane.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppColor.primary, in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("「\(node.storyDisplayText)」を送信")
        .accessibilityHint("会話を次へ進めます")
    }

    private var manualAdvanceButton: some View {
        Button {
            onPresentNode()
            onAdvance()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: manualAdvanceSymbol)
                    .accessibilityHidden(true)
                Text(manualAdvanceLabel)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(Capsule())
                .background(AppColor.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(manualAdvanceLabel)
        .accessibilityHint(isCloseButton ? "会話を終了してメニューに戻ります" : "会話を次へ進めます")
    }

    @ViewBuilder
    private var rioAvatar: some View {
        if let effectivePortrait {
            StoryAssetView(
                assetID: effectivePortrait,
                purpose: .image,
                contentMode: .fill,
                cornerRadius: 15
            )
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(AppColor.border))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(AppColor.primary)
                .frame(width: 30, height: 30)
                .background(AppColor.primarySoft, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("story-chat-bottom-spacing", anchor: .bottom)
        }
    }

}

private struct FullscreenNarrationAdvanceIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -2

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.callout.bold())
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 24, height: 20)
            .offset(y: offset)
            .onAppear {
                guard !reduceMotion else {
                    offset = 0
                    return
                }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    offset = 2
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// チャットを残したまま読む重要な地の文。連続する行の間は暗幕を維持する。
struct FullscreenChatNarrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let node: StoryNode
    let canAdvance: Bool
    let onPresentNode: () -> Void
    let onAdvance: () -> Void

    @State private var hasEntered = false
    @State private var displayedText = ""
    @State private var isTextVisible = false
    @State private var readyNodeID: String?

    var body: some View {
        ZStack {
            // 下の吹き出しの文字が透けて白文字と重ならない濃さにする。
            Color.black.opacity(0.80)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    Text(displayedText)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        .opacity(isTextVisible ? 1 : 0)
                }
            }
        }
        .overlay(alignment: .bottom) {
            // ADVのテキストウィンドウと同じく、タップで次へ進めることを示す。
            FullscreenNarrationAdvanceIndicator()
                .padding(.bottom, 32)
                .opacity(readyNodeID == node.nodeId && canAdvance ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: readyNodeID)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAdvance, readyNodeID == node.nodeId else { return }
            onAdvance()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isTextVisible ? displayedText : "ナレーション")
        .accessibilityHint("ダブルタップで次へ進みます")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard canAdvance, readyNodeID == node.nodeId else { return }
            onAdvance()
        }
        .task(id: node.nodeId) {
            let nodeID = node.nodeId
            readyNodeID = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                isTextVisible = false
            }
            let delay = hasEntered ? 0.18 : 0.35
            hasEntered = true
            do {
                // 最初は操作UIが消えるのを待つ。以降は地の文のみを短く切り替える。
                if !reduceMotion { try await Task.sleep(for: .seconds(delay)) }
                try Task.checkCancellation()
                displayedText = node.storyDisplayText
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isTextVisible = true
                }
                onPresentNode()
                if !reduceMotion { try await Task.sleep(for: .seconds(0.18)) }
                try Task.checkCancellation()
                readyNodeID = nodeID
                AccessibilityNotification.Announcement(node.storyDisplayText).post()
            } catch { return }
        }
    }
}

enum ChatStoryPresentationPolicy {
    static func usesChatCompletion(for scenarioType: StoryScenarioType) -> Bool {
        scenarioType == .daily || scenarioType == .smallEvent
    }

    static func usesFixedActionArea(for scenarioType: StoryScenarioType) -> Bool {
        switch scenarioType {
        case .daily, .prologue, .smallEvent, .middleEvent, .largeEvent:
            return true
        case .unknown:
            return false
        }
    }

    /// イベントの主人公の発言は、本文入りの入力欄として見せる。
    /// 日々の会話は次の発言を先に見せないため「返信する」ボタンのまま。
    static func usesPrefilledComposer(node: StoryNode, scenarioType: StoryScenarioType) -> Bool {
        guard node.isPlayerSpeaker, !node.storyDisplayText.isEmpty else { return false }
        switch scenarioType {
        case .prologue, .smallEvent, .middleEvent, .largeEvent:
            return true
        case .daily, .unknown:
            return false
        }
    }

    static func isUnsentPlayerMessage(node: StoryNode, canAdvance: Bool) -> Bool {
        canAdvance && node.isPlayerSpeaker && node.messageType == .text
    }

    /// 選択肢の行は送信前の入力欄。発言として残すのは選択後に生成される返信のみ。
    /// キャラクターの問いかけが含まれる行は通常の会話として残す。
    static func isChoicePlaceholder(node: StoryNode, scenarioType: StoryScenarioType) -> Bool {
        scenarioType == .daily
            && (node.choiceId != nil || node.messageType == .choice)
            && (node.isPlayerSpeaker || node.storyDisplayText.isEmpty)
    }

    static func manualAdvanceLabel(
        node: StoryNode,
        scenarioType: StoryScenarioType,
        isInitialEventPlayerMessage: Bool = false,
        isTerminalNode: Bool = false
    ) -> String {
        if isTerminalNode, !node.isPlayerSpeaker,
           StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: scenarioType) {
            return "閉じる"
        }
        guard node.isPlayerSpeaker else { return "次へ" }
        switch scenarioType {
        case .prologue, .smallEvent, .middleEvent, .largeEvent:
            if !node.storyDisplayText.isEmpty {
                return node.storyDisplayText
            }
            return isInitialEventPlayerMessage ? "送信する" : "返信する"
        case .daily, .unknown:
            return "返信する"
        }
    }
}

enum EventChatSystemPresentationPolicy {
    /// `screen_mode=chat` の描画側から利用する。画面モードは直前のsceneから継承してもよい。
    static func usesFullscreenNarration(node: StoryNode) -> Bool {
        node.uiVariant == .fullscreenNarration
            && node.messageType == .text
            && !node.storyDisplayText.isEmpty
    }

    static func usesInlineNarration(node: StoryNode) -> Bool {
        guard node.uiVariant != .fullscreenNarration,
              node.messageType == .text,
              !node.storyDisplayText.isEmpty else { return false }
        return isSystemLike(node) || node.uiVariant == .narration
    }

    /// 地の文のうち心の声は区切り線なしで出す。区切り線は場面転換・時間経過・endに限る。
    static func usesInlineMonologue(node: StoryNode) -> Bool {
        guard usesInlineNarration(node: node) else { return false }
        if node.uiVariant == .narration { return true }
        return node.uiVariant == nil && node.normalizedSpeakerKey == "narrator"
    }

    static func requiresManualAdvance(node: StoryNode, scenarioType: StoryScenarioType) -> Bool {
        isMiddleOrLargeEvent(scenarioType) && usesInlineNarration(node: node)
    }

    static func omitsFromChatHistory(
        node: StoryNode,
        scenarioType: StoryScenarioType
    ) -> Bool {
        if node.uiVariant == .fullscreenNarration { return true }
        guard isMiddleOrLargeEvent(scenarioType) else { return false }
        return isSystemLike(node) && node.storyDisplayText.isEmpty
    }

    private static func isMiddleOrLargeEvent(
        _ scenarioType: StoryScenarioType
    ) -> Bool {
        switch scenarioType {
        case .prologue, .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }

    private static func isSystemLike(_ node: StoryNode) -> Bool {
        ["system", "narrator"].contains(node.normalizedSpeakerKey)
    }
}

private struct RioTypingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColor.primary)
            Text("入力中…")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColor.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppColor.surface, in: Capsule())
        .overlay(Capsule().stroke(AppColor.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央が入力中")
    }
}

struct ChatStoryCompletionView: View {
    let visibleNodes: [StoryNode]
    var scenarioType: StoryScenarioType = .smallEvent
    let onClose: () -> Void

    private let bottomAnchorID = "story-chat-completion-bottom"

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleNodes.filter {
                                $0.uiVariant != .fullscreenNarration
                                && !ChatStoryPresentationPolicy.isChoicePlaceholder(
                                    node: $0,
                                    scenarioType: scenarioType
                                )
                            }) { messageNode in
                                StoryChatBubble(
                                    node: messageNode,
                                    scenarioType: scenarioType,
                                    portraitAssetID: messageNode.portrait,
                                    cgAssetID: messageNode.cg
                                )
                                .id(messageNode.nodeId)
                            }

                            ChatSystemMessageView(text: "end")

                            Color.clear
                                .frame(height: 16)
                                .id(bottomAnchorID)
                                .accessibilityHidden(true)
                        }
                        .padding(16)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .padding(.top, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                closeActionArea
            }
        }
    }

    private var closeActionArea: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: onClose) {
                Text("閉じる")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Capsule())
                    .background(AppColor.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("会話を閉じます")
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 81)
        .safeAreaPadding(.bottom, 8)
        .background(AppColor.background)
    }
}

private struct StoryChatBubble: View {
    let node: StoryNode
    let scenarioType: StoryScenarioType
    let portraitAssetID: String?
    let cgAssetID: String?

    private var speakerKey: String {
        node.normalizedSpeakerKey
    }

    private var isUser: Bool {
        node.isPlayerSpeaker
    }

    private var isSystem: Bool {
        speakerKey == "system"
    }

    private var isChatSystemMessage: Bool {
        EventChatSystemPresentationPolicy.usesInlineNarration(node: node)
            || (ChatStoryPresentationPolicy.usesChatCompletion(for: scenarioType) && isSystem)
    }

    var body: some View {
        if EventChatSystemPresentationPolicy.usesInlineMonologue(node: node) {
            ChatMonologueView(text: node.storyDisplayText)
        } else if isChatSystemMessage {
            chatSystemMessage
        } else if isSystem {
            HStack {
                Spacer(minLength: 28)
                bubbleContent
                Spacer(minLength: 28)
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser {
                    Spacer(minLength: 48)
                    bubbleContent
                } else {
                    characterAvatar
                    bubbleContent
                    Spacer(minLength: 48)
                }
            }
        }
    }

    private var chatSystemMessage: some View {
        ChatSystemMessageView(text: node.storyDisplayText)
    }

    @ViewBuilder
    private var characterAvatar: some View {
        if let portraitAssetID {
            StoryAssetView(
                assetID: portraitAssetID,
                purpose: .image,
                contentMode: .fill,
                cornerRadius: 15
            )
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(AppColor.border))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(AppColor.primary)
                .frame(width: 30, height: 30)
                .background(AppColor.primarySoft, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch node.uiVariant ?? .dialogue {
        case .titleCard:
            StoryTitleCardView(node: node)
        case .narration, .fullscreenNarration, .beat:
            StoryNarrationView(node: node)
        case .sceneTransition:
            StorySceneTransitionView(node: node)
        case .monologue:
            StoryMonologueView(node: node)
        case .typing:
            StoryTypingView(node: node)
        case .audioMessage:
            StoryAudioMessageView(node: node)
        case .imageMessage:
            StoryImageMessageView(node: node)
        case .cg:
            StoryAssetView(
                assetID: cgAssetID,
                purpose: .cg,
                contentMode: .fit,
                cornerRadius: 14
            )
            .frame(maxWidth: 280, minHeight: 160, maxHeight: 320)
        case .dialogue, .modal:
            chatTextBubble
        case .incomingCall, .recording, .callEnd, .outgoingCall, .callConnected, .unknown:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        }
    }

    @ViewBuilder
    private var chatTextBubble: some View {
        switch node.messageType {
        case .image:
            StoryImageMessageView(node: node)
        case .action:
            StoryNarrationView(node: node)
        case .text, .choice, .unknown:
            VStack(alignment: .leading, spacing: 4) {
                if let speakerName = node.speakerName, !speakerName.isEmpty, !isUser {
                    Text(speakerName)
                        .font(.caption2.bold())
                        .foregroundStyle(AppColor.primary)
                }
                Text(node.storyDisplayText)
                    .font(.body)
                    .foregroundStyle(AppColor.text)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                isUser ? AppColor.primarySoft : AppColor.surface,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppColor.border.opacity(isUser ? 0 : 1))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// チャット中の主人公の心の声。直前の発言への反応なので、区切り線は付けず会話の流れに置く。
private struct ChatMonologueView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// 場面転換・時間経過・会話の終わりを示す区切り。
private struct ChatSystemMessageView: View {
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            divider

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            divider
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColor.secondary.opacity(0.45))
            .frame(minWidth: 20, maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
