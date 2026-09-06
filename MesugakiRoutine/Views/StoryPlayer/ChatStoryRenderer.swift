import SwiftUI

/// チャット表示専用のrenderer。表示済みnode列を受け取り、進行処理はcallbackへ返す。
struct ChatStoryRenderer: View {
    let node: StoryNode
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

    private var effectiveBackground: String? { backgroundAssetID ?? node.background }
    private var effectivePortrait: String? { portraitAssetID ?? node.portrait }
    private var effectiveCG: String? { cgAssetID ?? node.cg }
    private var canAdvance: Bool { choices.isEmpty && !isModalPresented && !isTyping }

    private var renderedNodes: [StoryNode] {
        guard !visibleNodes.contains(where: { $0.nodeId == node.nodeId }) else {
            return visibleNodes
        }
        return visibleNodes + [node]
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
                                    portraitAssetID: messageNode.nodeId == node.nodeId
                                        ? effectivePortrait
                                        : messageNode.portrait,
                                    cgAssetID: messageNode.nodeId == node.nodeId
                                        ? effectiveCG
                                        : messageNode.cg
                                )
                                    .id(messageNode.nodeId)
                            }

                            if isTyping {
                                HStack {
                                    StoryTypingView(node: node)
                                    Spacer(minLength: 52)
                                }
                                .id("story-chat-typing")
                            }
                        }
                        .padding(16)
                    }
                    .onAppear { scrollToLatest(proxy) }
                    .onChange(of: renderedNodes.count) { _, _ in scrollToLatest(proxy) }
                    .onChange(of: isTyping) { _, _ in scrollToLatest(proxy) }
                }

                if !choices.isEmpty {
                    Divider()
                    StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                        .padding(16)
                        .background(AppColor.background.opacity(0.96))
                } else if canAdvance {
                    Button(action: onAdvance) {
                        HStack(spacing: 6) {
                            Text("タップして次へ")
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(AppColor.surface.opacity(0.94))
                    .accessibilityLabel("次へ")
                }
            }

            if isModalPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                StoryModalView(node: node, onDismiss: onDismissModal)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = isTyping ? "story-chat-typing" : renderedNodes.last?.nodeId
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

private struct StoryChatBubble: View {
    let node: StoryNode
    let portraitAssetID: String?
    let cgAssetID: String?

    private var speakerKey: String {
        node.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isUser: Bool {
        ["user", "player", "protagonist"].contains(speakerKey)
    }

    private var isSystem: Bool {
        speakerKey == "system"
    }

    var body: some View {
        if isSystem {
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
