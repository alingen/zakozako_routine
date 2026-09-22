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
                        ),
                        textHorizontalPadding: textHorizontalPadding
                    )

                    if !choices.isEmpty {
                        StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
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
        if usesLandscapeStillLayout {
            return min(640, availableWidth * 0.95)
        }
        return .infinity
    }

    private var usesLandscapeStillLayout: Bool {
        scenarioType.supportsLandscapeStillPresentation && effectiveCG != nil
    }

    private var contentHorizontalPadding: CGFloat {
        usesLandscapeStillLayout ? 18 : 10
    }

    private var textHorizontalPadding: CGFloat {
        usesLandscapeStillLayout ? 48 : 32
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
    private func variantContent(
        textWindowMaxWidth: CGFloat,
        textHorizontalPadding: CGFloat
    ) -> some View {
        switch node.uiVariant ?? .dialogue {
        case .titleCard:
            StoryTitleCardView(node: node)
        case .narration, .beat, .sceneTransition, .monologue:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                horizontalPadding: textHorizontalPadding,
                onAdvance: canAdvance ? onAdvance : nil
            )
        case .dialogue:
            defaultMessageContent(
                textWindowMaxWidth: textWindowMaxWidth,
                textHorizontalPadding: textHorizontalPadding
            )
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
                    horizontalPadding: textHorizontalPadding,
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
    private func defaultMessageContent(
        textWindowMaxWidth: CGFloat,
        textHorizontalPadding: CGFloat
    ) -> some View {
        switch node.messageType {
        case .image:
            StoryImageMessageView(node: node)
        case .action:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                horizontalPadding: textHorizontalPadding,
                onAdvance: canAdvance ? onAdvance : nil
            )
        case .text, .choice, .unknown:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                horizontalPadding: textHorizontalPadding,
                onAdvance: canAdvance ? onAdvance : nil
            )
        }
    }
}

struct ADVTextWindow: View {
    let node: StoryNode
    let maxWidth: CGFloat
    let horizontalPadding: CGFloat
    let onAdvance: (() -> Void)?
    var backgroundStyle: ADVTextWindowBackgroundStyle = .material

    private var normalizedSpeaker: String {
        node.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isProtagonist: Bool {
        ["user", "player", "protagonist"].contains(normalizedSpeaker)
            || node.storyDisplaySpeakerName == "主人公"
    }

    private var protagonistDisplayName: String {
        let nickname = AppSettingsStore.userName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? "主人公" : nickname
    }

    private var displaySpeakerName: String? {
        if normalizedSpeaker == "narrator" {
            return nil
        }

        if isProtagonist {
            return protagonistDisplayName
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
        default:
            return node.speaker.isEmpty ? nil : node.speaker
        }
    }

    private var displayText: String {
        ADVTextLayout.formatted(node.storyDisplayText)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                let textWidth = max(0, proxy.size.width - horizontalPadding * 2)

                Text(displayText)
                    .font(.system(size: ADVTextLayout.fontSize(for: textWidth)))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(ADVTextLayout.maximumLines)
                    .truncationMode(.tail)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: maxWidth)
        .frame(height: 136, alignment: .topLeading)
        .background {
            switch backgroundStyle {
            case .material:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            case .baseColor:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.background)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if let displaySpeakerName {
                Text(displaySpeakerName)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppColor.primary)
                    }
                    .offset(x: horizontalPadding, y: -19)
            }
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

enum ADVTextLayout {
    static let maximumCharactersPerLine = 18
    static let maximumLines = 3

    private static let minimumFontSize: CGFloat = 13
    private static let maximumFontSize: CGFloat = 22
    private static let widthSafetyFactor: CGFloat = 0.96

    /// `[br]` と既存の改行を優先し、それぞれの行を18文字以内に収める。
    static func formatted(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[br]", with: "\n")

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap(wrappedLines)
            .joined(separator: "\n")
    }

    /// 18文字分が収まる大きさを端末幅から求め、極端に大小にならない範囲へ収める。
    static func fontSize(for availableTextWidth: CGFloat) -> CGFloat {
        guard availableTextWidth.isFinite, availableTextWidth > 0 else {
            return minimumFontSize
        }

        let fittedSize = availableTextWidth
            / CGFloat(maximumCharactersPerLine)
            * widthSafetyFactor
        return min(maximumFontSize, max(minimumFontSize, fittedSize))
    }

    private static func wrappedLines(_ line: Substring) -> [String] {
        guard !line.isEmpty else { return [""] }

        var result: [String] = []
        var remainder = line[...]

        while !remainder.isEmpty {
            let endIndex = remainder.index(
                remainder.startIndex,
                offsetBy: maximumCharactersPerLine,
                limitedBy: remainder.endIndex
            ) ?? remainder.endIndex
            result.append(String(remainder[..<endIndex]))
            remainder = remainder[endIndex...]
        }

        return result
    }
}

enum ADVTextWindowBackgroundStyle {
    case material
    case baseColor
}
