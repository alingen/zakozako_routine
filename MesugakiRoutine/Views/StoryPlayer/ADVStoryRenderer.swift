import SwiftUI

/// ADV表示専用のrenderer。シナリオ遷移は行わず、渡されたnodeと表示状態だけを描画する。
struct ADVStoryRenderer: View {
    let node: StoryNode
    var backgroundAssetID: String?
    var portraitAssetID: String?
    var cgAssetID: String?
    var choices: [StoryChoice] = []
    var isModalPresented = false
    let onAdvance: () -> Void
    let onSelectChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void

    private var effectiveBackground: String? { backgroundAssetID ?? node.background }
    private var effectivePortrait: String? { portraitAssetID ?? node.portrait }
    private var effectiveCG: String? { cgAssetID ?? node.cg }
    private var canAdvance: Bool { choices.isEmpty && !isModalPresented }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StoryAssetView(
                    assetID: effectiveBackground,
                    purpose: .background,
                    contentMode: .fill
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                Color.black.opacity(effectiveCG == nil ? 0.12 : 0.28)

                if let effectiveCG {
                    StoryAssetView(assetID: effectiveCG, purpose: .cg, contentMode: .fit)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .transition(.opacity)
                } else if let effectivePortrait {
                    StoryAssetView(assetID: effectivePortrait, purpose: .image, contentMode: .fit)
                        .frame(
                            maxWidth: proxy.size.width * 0.78,
                            maxHeight: proxy.size.height * 0.72,
                            alignment: .bottom
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 150)
                }

                if canAdvance {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onAdvance)
                        .accessibilityElement()
                        .accessibilityLabel("次へ")
                        .accessibilityAddTraits(.isButton)
                }

                VStack(spacing: 14) {
                    variantContent

                    if !choices.isEmpty {
                        StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: variantAlignment)

                if isModalPresented {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    StoryModalView(node: node, onDismiss: onDismissModal)
                }
            }
            .clipped()
        }
        .background(AppColor.background)
    }

    private var variantAlignment: Alignment {
        switch node.uiVariant ?? .dialogue {
        case .titleCard, .cg:
            return .center
        default:
            return .bottom
        }
    }

    @ViewBuilder
    private var variantContent: some View {
        switch node.uiVariant ?? .dialogue {
        case .titleCard:
            StoryTitleCardView(node: node)
        case .narration, .beat, .sceneTransition, .monologue:
            ADVTextWindow(node: node)
        case .dialogue:
            defaultMessageContent
        case .typing:
            StoryTypingView(node: node)
        case .audioMessage:
            StoryAudioMessageView(node: node)
        case .imageMessage:
            StoryImageMessageView(node: node)
        case .cg:
            EmptyView()
        case .modal:
            if !isModalPresented {
                ADVTextWindow(node: node)
            }
        case .incomingCall, .recording, .callEnd, .outgoingCall, .callConnected:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        case .unknown:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        }
    }

    @ViewBuilder
    private var defaultMessageContent: some View {
        switch node.messageType {
        case .image:
            StoryImageMessageView(node: node)
        case .action:
            ADVTextWindow(node: node)
        case .text, .choice, .unknown:
            ADVTextWindow(node: node)
        }
    }
}

private struct ADVTextWindow: View {
    let node: StoryNode

    private var normalizedSpeaker: String {
        node.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSystemMessage: Bool {
        ["system", "narrator"].contains(normalizedSpeaker)
    }

    private var displaySpeakerName: String {
        if let providedName = node.storyDisplaySpeakerName {
            return providedName.lowercased() == "system" ? "システム" : providedName
        }

        switch normalizedSpeaker {
        case "system":
            return "システム"
        case "narrator":
            return "地の文"
        case "rio", "character":
            return "莉央"
        case "user", "player", "protagonist":
            return "主人公"
        default:
            return node.speaker
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displaySpeakerName)
                .font(.title3.bold())
                .foregroundStyle(isSystemMessage ? AppColor.secondary : AppColor.primary)
                .lineLimit(1)

            Text(node.storyDisplayText)
                .font(.body)
                .foregroundStyle(AppColor.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 136, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
