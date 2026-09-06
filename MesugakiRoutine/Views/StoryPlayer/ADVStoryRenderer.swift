import SwiftUI

/// ADV表示専用のrenderer。シナリオ遷移は行わず、渡されたnodeと表示状態だけを描画する。
struct ADVStoryRenderer: View {
    let node: StoryNode
    let scenarioType: StoryScenarioType
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

    private var advancesFromTextWindow: Bool {
        switch node.uiVariant ?? .dialogue {
        case .narration, .beat, .sceneTransition, .monologue:
            return true
        case .dialogue:
            return node.messageType != .image
        case .modal:
            return !isModalPresented
        default:
            return false
        }
    }

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

                // Nodes without a text window retain a full-screen advance
                // target. Dialogue and narration advance only from their
                // visible window so an accidental background tap is ignored.
                if canAdvance, !advancesFromTextWindow {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onAdvance)
                        .accessibilityElement()
                        .accessibilityLabel("次へ")
                        .accessibilityAddTraits(.isButton)
                }

                VStack(spacing: 14) {
                    variantContent(
                        textWindowMaxWidth: textWindowMaxWidth(
                            availableWidth: proxy.size.width
                        )
                    )

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

    private func textWindowMaxWidth(availableWidth: CGFloat) -> CGFloat {
        switch scenarioType {
        case .middleEvent, .largeEvent:
            return min(720, availableWidth * 0.8)
        case .daily, .smallEvent, .unknown:
            return .infinity
        }
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
    private func variantContent(textWindowMaxWidth: CGFloat) -> some View {
        switch node.uiVariant ?? .dialogue {
        case .titleCard:
            StoryTitleCardView(node: node)
        case .narration, .beat, .sceneTransition, .monologue:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                onAdvance: canAdvance ? onAdvance : nil
            )
        case .dialogue:
            defaultMessageContent(textWindowMaxWidth: textWindowMaxWidth)
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
                ADVTextWindow(
                    node: node,
                    maxWidth: textWindowMaxWidth,
                    onAdvance: canAdvance ? onAdvance : nil
                )
            }
        case .incomingCall, .recording, .callEnd, .outgoingCall, .callConnected:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        case .unknown:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        }
    }

    @ViewBuilder
    private func defaultMessageContent(textWindowMaxWidth: CGFloat) -> some View {
        switch node.messageType {
        case .image:
            StoryImageMessageView(node: node)
        case .action:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                onAdvance: canAdvance ? onAdvance : nil
            )
        case .text, .choice, .unknown:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                onAdvance: canAdvance ? onAdvance : nil
            )
        }
    }
}

private struct ADVTextWindow: View {
    let node: StoryNode
    let maxWidth: CGFloat
    let onAdvance: (() -> Void)?

    private var normalizedSpeaker: String {
        node.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displaySpeakerName: String? {
        if normalizedSpeaker == "narrator" {
            return nil
        }

        if let providedName = node.storyDisplaySpeakerName {
            switch providedName.lowercased() {
            case "system":
                return "システム"
            case "地の文":
                return nil
            default:
                return providedName
            }
        }

        switch normalizedSpeaker {
        case "system":
            return "システム"
        case "rio", "character":
            return "莉央"
        case "user", "player", "protagonist":
            return "主人公"
        default:
            return node.speaker.isEmpty ? nil : node.speaker
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(node.storyDisplayText)
                .font(.body)
                .foregroundStyle(AppColor.text)
                .lineLimit(3)
                .padding(.horizontal, 30)
                .padding(.top, displaySpeakerName == nil ? 20 : 28)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let displaySpeakerName {
                Text(displaySpeakerName)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        AppColor.primary,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .offset(x: 24, y: -16)
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(height: 136, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            onAdvance?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onAdvance == nil ? [] : .isButton)
        .accessibilityHint(onAdvance == nil ? "" : "ダブルタップして次へ進みます")
    }
}
