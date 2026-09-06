import SwiftUI

/// 通話表示専用のrenderer。実際の発着信・録音は行わず、CMSの演出状態だけを描画する。
struct CallStoryRenderer: View {
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
        ZStack {
            LinearGradient(
                colors: [AppColor.secondary.opacity(0.92), AppColor.text],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let effectiveBackground {
                StoryAssetView(
                    assetID: effectiveBackground,
                    purpose: .background,
                    contentMode: .fill
                )
                .ignoresSafeArea()
                .opacity(0.24)
            }

            if let effectiveCG {
                StoryAssetView(assetID: effectiveCG, purpose: .cg, contentMode: .fit)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.26))
            }

            VStack(spacing: 22) {
                callStatus

                if effectiveCG == nil {
                    callerVisual
                }

                primaryContent

                Spacer(minLength: 12)

                if !choices.isEmpty {
                    StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                } else if canAdvance {
                    Button(action: onAdvance) {
                        Label(advanceLabel, systemImage: advanceSymbol)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .frame(minHeight: 52)
                            .background(advanceColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("シナリオを次へ進めます")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 28)

            if isModalPresented {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                StoryModalView(node: node, onDismiss: onDismissModal)
            }
        }
    }

    private var callerVisual: some View {
        Group {
            if let effectivePortrait {
                StoryAssetView(
                    assetID: effectivePortrait,
                    purpose: .image,
                    contentMode: .fill,
                    cornerRadius: 90
                )
            } else {
                ZStack {
                    Circle().fill(AppColor.primarySoft)
                    Image(systemName: "person.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColor.primary)
                }
                .accessibilityLabel("通話相手")
            }
        }
        .frame(width: 172, height: 172)
        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 3))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
    }

    private var callStatus: some View {
        VStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(.white)
            Text(statusLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch node.uiVariant ?? .callConnected {
        case .audioMessage:
            StoryAudioMessageView(node: node)
        case .imageMessage, .cg:
            StoryImageMessageView(node: node)
        case .typing:
            StoryTypingView(node: node)
        case .monologue:
            StoryMonologueView(node: node)
        case .narration, .beat:
            StoryNarrationView(node: node)
        case .titleCard:
            StoryTitleCardView(node: node)
        case .sceneTransition:
            StorySceneTransitionView(node: node)
        case .dialogue, .incomingCall, .recording, .callEnd, .outgoingCall, .callConnected, .modal:
            if let text = node.text, !text.isEmpty {
                Text(text)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityLabel(text)
            }
        case .unknown:
            StoryUnknownVariantView(node: node, variant: node.uiVariant)
        }
    }

    private var statusLabel: String {
        switch node.uiVariant {
        case .incomingCall: return "着信中"
        case .outgoingCall: return "発信中"
        case .callConnected: return "通話中"
        case .recording: return "音声メッセージを録音中"
        case .callEnd: return "通話終了"
        default: return "通話"
        }
    }

    private var statusSymbol: String {
        switch node.uiVariant {
        case .incomingCall: return "phone.arrow.down.left"
        case .outgoingCall: return "phone.arrow.up.right"
        case .recording: return "waveform.circle"
        case .callEnd: return "phone.down.fill"
        default: return "phone.fill"
        }
    }

    private var advanceLabel: String {
        switch node.uiVariant {
        case .incomingCall: return "電話に出る"
        case .callEnd: return "閉じる"
        default: return "次へ"
        }
    }

    private var advanceSymbol: String {
        switch node.uiVariant {
        case .incomingCall: return "phone.fill"
        case .callEnd: return "xmark"
        default: return "chevron.right"
        }
    }

    private var advanceColor: Color {
        switch node.uiVariant {
        case .incomingCall: return AppColor.success
        case .callEnd: return AppColor.error
        default: return AppColor.primary
        }
    }
}
