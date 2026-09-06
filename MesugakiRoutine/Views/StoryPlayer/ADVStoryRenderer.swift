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
                            maxHeight: proxy.size.height * 0.66,
                            alignment: .bottom
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 116)
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
        case .titleCard, .sceneTransition, .cg:
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
        case .narration, .beat:
            StoryNarrationView(node: node)
        case .dialogue:
            defaultMessageContent
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
            EmptyView()
        case .modal:
            if !isModalPresented {
                StoryDialogueView(node: node)
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
            StoryNarrationView(node: node)
        case .text, .choice, .unknown:
            StoryDialogueView(node: node)
        }
    }
}
