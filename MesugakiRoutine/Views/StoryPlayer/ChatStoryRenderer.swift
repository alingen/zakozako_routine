import SwiftUI

/// チャット表示専用のrenderer。表示済みnode列を受け取り、進行処理はcallbackへ返す。
struct ChatStoryRenderer: View {
    let node: StoryNode
    let scenarioType: StoryScenarioType
    var visibleNodes: [StoryNode] = []
    var backgroundAssetID: String?
    var portraitAssetID: String?
    var cgAssetID: String?
    var choices: [StoryChoice] = []
    var isTyping = false
    var isModalPresented = false
    let onAdvance: () -> Void
    let onSelectChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void

    @State private var typingStartedRioNodeID: String?
    @State private var revealedRioNodeID: String?
    @State private var revealedSystemNodeID: String?

    private var effectiveBackground: String? { backgroundAssetID ?? node.background }
    private var effectivePortrait: String? { portraitAssetID ?? node.portrait }
    private var effectiveCG: String? { cgAssetID ?? node.cg }
    private var canAdvance: Bool { choices.isEmpty && !isModalPresented && !isTyping }
    private var shouldAutoAdvance: Bool {
        guard canAdvance else { return false }
        if scenarioType == .smallEvent {
            return !isWaitingToSendPlayerMessage
        }
        return node.isRioSpeaker && node.messageType == .text
    }
    private var isWaitingToSendPlayerMessage: Bool {
        canAdvance && node.isPlayerSpeaker && node.messageType == .text
    }
    private var isWaitingForRioMessage: Bool {
        shouldAutoAdvance
            && node.isRioSpeaker
            && node.messageType == .text
            && revealedRioNodeID != node.nodeId
    }
    private var isShowingRioTyping: Bool {
        isWaitingForRioMessage && typingStartedRioNodeID == node.nodeId
    }
    private var isWaitingForSystemMessage: Bool {
        shouldAutoAdvance
            && scenarioType == .smallEvent
            && node.normalizedSpeakerKey == "system"
            && node.messageType == .text
            && revealedSystemNodeID != node.nodeId
    }

    private var isInitialSmallEventPlayerMessage: Bool {
        guard scenarioType == .smallEvent, isWaitingToSendPlayerMessage else {
            return false
        }
        return !visibleNodes.contains {
            $0.nodeId != node.nodeId && ($0.isPlayerSpeaker || $0.isRioSpeaker)
        }
    }

    private var manualAdvanceLabel: String {
        guard node.isPlayerSpeaker else { return "次へ" }
        if scenarioType == .smallEvent,
           let replyText = node.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !replyText.isEmpty {
            return replyText
        }
        return isInitialSmallEventPlayerMessage ? "送信する" : "返信する"
    }

    private var manualAdvanceSymbol: String {
        node.isPlayerSpeaker ? "paperplane.fill" : "chevron.right"
    }

    private let rioResponsePauseNanoseconds: UInt64 = 700_000_000
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
            (!isWaitingToSendPlayerMessage
                && !isWaitingForRioMessage
                && !isWaitingForSystemMessage)
                || $0.nodeId != node.nodeId
        }
        guard !isWaitingToSendPlayerMessage,
              !isWaitingForRioMessage,
              !isWaitingForSystemMessage,
              !sentNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return sentNodes
        }
        return sentNodes + [node]
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            if let effectiveBackground {
                StoryAssetView(
                    assetID: effectiveBackground,
                    purpose: .background,
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .opacity(0.18)
            }

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(renderedNodes) { messageNode in
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
                    .onChange(of: renderedNodes.count) { _, _ in scrollToLatest(proxy) }
                    .onChange(of: isTyping) { _, _ in scrollToLatest(proxy) }
                    .onChange(of: isShowingRioTyping) { _, _ in scrollToLatest(proxy) }
                }
                .padding(.top, 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                actionArea
            }

            if isModalPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                StoryModalView(node: node, onDismiss: onDismissModal)
            }
        }
        .task(id: node.nodeId) {
            guard shouldAutoAdvance else { return }
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
                } else {
                    try await Task<Never, Never>.sleep(
                        nanoseconds: automaticContentDelayNanoseconds
                    )
                }
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onAdvance()
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if scenarioType == .smallEvent {
            fixedSmallEventActionArea
        } else if !choices.isEmpty {
            Divider()
            StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                .padding(16)
                .background(AppColor.background.opacity(0.96))
        } else if canAdvance && !node.isRioSpeaker {
            manualAdvanceArea
        }
    }

    private var fixedSmallEventActionArea: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if !choices.isEmpty {
                    StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                } else if canAdvance && !shouldAutoAdvance {
                    manualAdvanceButton
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
        .frame(height: 81)
        .safeAreaPadding(.bottom, 8)
        .background(AppColor.background)
    }

    private var manualAdvanceArea: some View {
        VStack(spacing: 0) {
            Divider()
            manualAdvanceButton
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 81)
        .safeAreaPadding(.bottom, 8)
        .background(AppColor.background)
    }

    private var manualAdvanceButton: some View {
        Button(action: onAdvance) {
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
        .accessibilityHint("会話を次へ進めます")
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

    private var isSmallEventSystemMessage: Bool {
        scenarioType == .smallEvent && isSystem
    }

    var body: some View {
        if isSmallEventSystemMessage {
            smallEventSystemMessage
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

    private var smallEventSystemMessage: some View {
        Text(node.text ?? "")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(AppColor.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("場面転換。\(node.text ?? "")")
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
        case .narration, .beat:
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
                Text(node.text ?? "")
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

private extension StoryNode {
    var normalizedSpeakerKey: String {
        speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isPlayerSpeaker: Bool {
        ["user", "player", "protagonist"].contains(normalizedSpeakerKey)
    }

    var isRioSpeaker: Bool {
        ["rio", "character"].contains(normalizedSpeakerKey)
            || speakerName?.trimmingCharacters(in: .whitespacesAndNewlines) == "莉央"
    }
}
