import SwiftUI

enum ADVTextWindowPresentationPolicy {
    static func showsContent(for node: StoryNode) -> Bool {
        if node.command?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == "portrait_hesitate" {
            return false
        }
        return node.uiVariant != .sceneTransition || !node.storyDisplayText.isEmpty
    }
}

/// ADV表示専用のrenderer。シナリオ遷移は行わず、渡されたnodeと表示状態だけを描画する。
struct ADVStoryRenderer: View {
    let node: StoryNode
    let scenarioType: StoryScenarioType
    var backgroundAssetID: String?
    var portraitAssetID: String?
    var cgAssetID: String?
    var choices: [StoryChoice] = []
    var isModalPresented = false
    var openingRevealPhase: ADVOpeningRevealPhase = .text
    var delaysTextAfterBlackout = false
    var showsHesitationBubble = false
    var playbackMode: ADVPlaybackMode = .manual
    var isPlaybackPaused = false
    var isAutomationAvailable = true
    var isLogAvailable = false
    var showsPlaybackControls = true
    var allowsSkip = true
    let onAdvance: (StoryAdvancePace) -> Void
    let onSelectChoice: (StoryChoice) -> Void
    let onDismissModal: () -> Void
    var onTextWindowTap: () -> Void = {}
    var onSkip: () -> Void = {}
    var onClose: () -> Void = {}
    var onShowLog: () -> Void = {}
    var onToggleAuto: () -> Void = {}
    var onToggleFastForward: () -> Void = {}

    @State private var revealedBlackoutNodeID: String?

    private var effectiveBackground: String? { backgroundAssetID ?? node.background }
    private var effectivePortrait: String? { portraitAssetID ?? node.portrait }
    private var effectiveCG: String? { cgAssetID ?? node.cg }
    private var canAdvance: Bool { choices.isEmpty && !isModalPresented }
    private var reservedControlBarHeight: CGFloat { showsPlaybackControls ? 68 : 0 }
    private var isBlackoutTextReady: Bool {
        !delaysTextAfterBlackout || revealedBlackoutNodeID == node.nodeId
    }
    private var blackoutTextRevealTaskID: String {
        "\(node.nodeId)|\(delaysTextAfterBlackout)"
    }

    private var allowsAutomaticNonTextAdvance: Bool {
        switch node.uiVariant ?? .dialogue {
        case .titleCard, .cg:
            return true
        case .dialogue:
            return node.messageType == .image
        default:
            return false
        }
    }

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
            // 操作バーはhome indicatorを避けるが、背景・立ち絵は画面下端まで描く。
            let bottomInset = proxy.safeAreaInsets.bottom

            ZStack {
                Color.black
                    .ignoresSafeArea()

                if openingRevealPhase.showsScene {
                    if let effectiveBackground {
                        StoryAssetView(
                            assetID: effectiveBackground,
                            purpose: .background,
                            contentMode: .fill
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height + bottomInset)
                        .clipped()
                        // レイアウト上の高さは変えず、下端の安全領域へはみ出して描く。
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }

                    Color.black.opacity(effectiveCG == nil ? 0.12 : 0.28)
                        .ignoresSafeArea()

                    if let effectiveCG {
                        StoryAssetView(assetID: effectiveCG, purpose: .cg, contentMode: .fit)
                            .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                            .transition(.opacity)
                    } else {
                        ZStack {
                            if let effectivePortrait {
                                StoryAssetView(
                                    assetID: effectivePortrait,
                                    purpose: .image,
                                    contentMode: .fit
                                )
                                .frame(
                                    width: max(
                                        proxy.size.width * 1.4,
                                        proxy.size.height * 0.97 * 2 / 3
                                    ),
                                    height: proxy.size.height * 0.97,
                                    alignment: .bottom
                                )
                                // Place the head below the top UI and crop the
                                // legs around the knees at the bottom edge.
                                .offset(y: proxy.size.height * 0.19)
                                // Keep the oversized portrait from widening
                                // the background and dialogue layout.
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height,
                                    alignment: .bottom
                                )
                                // Fade an entrance; keep the same view identity
                                // so expression changes replace the image at once.
                                .transition(
                                    .asymmetric(insertion: .opacity, removal: .identity)
                                )

                                if showsHesitationBubble {
                                    ADVHesitationBubble()
                                        .id(node.nodeId)
                                        .frame(width: 82, height: 57)
                                        .position(
                                            x: min(proxy.size.width - 47, proxy.size.width * 0.76),
                                            y: max(100, proxy.size.height * 0.25)
                                        )
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .animation(.easeInOut(duration: 0.125), value: effectivePortrait != nil)
                    }
                }

                // Nodes without a text window retain a full-screen advance
                // target. Dialogue and narration advance only from their
                // visible window so an accidental background tap is ignored.
                if openingRevealPhase.startsTextReveal,
                   canAdvance,
                   !advancesFromTextWindow {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onAdvance(.normal) }
                        .accessibilityElement()
                        .accessibilityLabel("次へ")
                        .accessibilityAddTraits(.isButton)
                }

                if openingRevealPhase.showsTextBox, isBlackoutTextReady {
                    VStack(spacing: 14) {
                        if ADVTextWindowPresentationPolicy.showsContent(for: node),
                           advancesFromTextWindow || openingRevealPhase.startsTextReveal {
                            variantContent(
                                textWindowMaxWidth: textWindowMaxWidth(
                                    availableWidth: proxy.size.width
                                ),
                                textHorizontalPadding: textHorizontalPadding(
                                    availableWidth: proxy.size.width
                                )
                            )
                        }

                        if openingRevealPhase.startsTextReveal, !choices.isEmpty {
                            StoryChoicePanel(choices: choices, onSelect: onSelectChoice)
                        }
                    }
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.bottom, 20 + reservedControlBarHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: variantAlignment)
                }

                if showsPlaybackControls,
                   openingRevealPhase.showsTextBox,
                   isBlackoutTextReady {
                    ADVPlaybackControlBar(
                        playbackMode: playbackMode,
                        isLogAvailable: isLogAvailable,
                        isAutomationAvailable: isAutomationAvailable,
                        isFastForwardEnabled: choices.isEmpty && !isModalPresented,
                        allowsSkip: allowsSkip,
                        onSkip: onSkip,
                        onClose: onClose,
                        onShowLog: onShowLog,
                        onToggleAuto: onToggleAuto,
                        onToggleFastForward: onToggleFastForward
                    )
                    .frame(maxWidth: min(460, proxy.size.width - 24))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(openingRevealPhase.startsTextReveal)
                    .accessibilityHidden(!openingRevealPhase.startsTextReveal)
                }

                if isModalPresented, openingRevealPhase.startsTextReveal {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    StoryModalView(node: node, onDismiss: onDismissModal)
                }
            }
            // 大きな立ち絵の横はみ出しは切りつつ、下端の安全領域までは表示する。
            .mask {
                Rectangle()
                    .padding(.bottom, -bottomInset)
            }
        }
        .background(AppColor.background)
        .task(id: blackoutTextRevealTaskID) {
            guard delaysTextAfterBlackout else { return }
            do {
                try await Task<Never, Never>.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            revealedBlackoutNodeID = node.nodeId
        }
        .task(id: automaticNonTextAdvanceTaskID) {
            await automaticallyAdvanceNonTextNodeIfNeeded()
        }
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

    private func textHorizontalPadding(availableWidth: CGFloat) -> CGFloat {
        if usesLandscapeStillLayout { return 48 }

        let estimatedWindowWidth = availableWidth - contentHorizontalPadding * 2
        let minimumWidthForEighteenCharacters = CGFloat(
            ADVTextLayout.maximumCharactersPerLine
        ) * 13
        return estimatedWindowWidth - 72 >= minimumWidthForEighteenCharacters ? 36 : 32
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
                onAdvance: canAdvance ? onAdvance : nil,
                onTextWindowTap: onTextWindowTap,
                playbackMode: playbackMode,
                isPlaybackPaused: isPlaybackPaused,
                isAutomationAvailable: isAutomationAvailable,
                isTextRevealEnabled: openingRevealPhase.startsTextReveal,
                isTypingEffectEnabled: true
            )
            .id(node.nodeId)
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
                    onAdvance: canAdvance ? onAdvance : nil,
                    onTextWindowTap: onTextWindowTap,
                    playbackMode: playbackMode,
                    isPlaybackPaused: isPlaybackPaused,
                    isAutomationAvailable: isAutomationAvailable,
                    isTextRevealEnabled: openingRevealPhase.startsTextReveal,
                    isTypingEffectEnabled: true
                )
                .id(node.nodeId)
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
                onAdvance: canAdvance ? onAdvance : nil,
                onTextWindowTap: onTextWindowTap,
                playbackMode: playbackMode,
                isPlaybackPaused: isPlaybackPaused,
                isAutomationAvailable: isAutomationAvailable,
                isTextRevealEnabled: openingRevealPhase.startsTextReveal,
                isTypingEffectEnabled: true
            )
            .id(node.nodeId)
        case .text, .choice, .unknown:
            ADVTextWindow(
                node: node,
                maxWidth: textWindowMaxWidth,
                horizontalPadding: textHorizontalPadding,
                onAdvance: canAdvance ? onAdvance : nil,
                onTextWindowTap: onTextWindowTap,
                playbackMode: playbackMode,
                isPlaybackPaused: isPlaybackPaused,
                isAutomationAvailable: isAutomationAvailable,
                isTextRevealEnabled: openingRevealPhase.startsTextReveal,
                isTypingEffectEnabled: true
            )
            .id(node.nodeId)
        }
    }

    private var automaticNonTextAdvanceTaskID: String {
        [
            node.nodeId,
            playbackMode.rawValue,
            String(canAdvance),
            String(advancesFromTextWindow),
            String(isPlaybackPaused),
            String(isAutomationAvailable),
            String(openingRevealPhase.rawValue),
        ].joined(separator: "|")
    }

    private func automaticallyAdvanceNonTextNodeIfNeeded() async {
        guard !advancesFromTextWindow,
              canAdvance,
              !isPlaybackPaused,
              isAutomationAvailable,
              allowsAutomaticNonTextAdvance,
              openingRevealPhase.startsTextReveal,
              playbackMode != .manual else {
            return
        }

        let delay = playbackMode == .fastForward
            ? ADVPlaybackTiming.fastAdvanceDelayNanoseconds
            : ADVPlaybackTiming.autoNonTextAdvanceDelayNanoseconds
        do {
            try await Task<Never, Never>.sleep(nanoseconds: delay)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        onAdvance(playbackMode == .fastForward ? .fastForward : .normal)
    }
}

enum ADVHesitationBubbleAnimation {
    static func visibleDotCount(elapsed: TimeInterval, reduceMotion: Bool) -> Int {
        if reduceMotion { return 3 }
        guard elapsed.isFinite else { return 1 }
        let cyclePosition = max(0, elapsed).truncatingRemainder(dividingBy: 1.05)
        return min(3, Int(cyclePosition / 0.35) + 1)
    }
}

private struct ADVHesitationBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if reduceMotion {
                bubble(visibleDotCount: 3)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    bubble(visibleDotCount: ADVHesitationBubbleAnimation.visibleDotCount(
                        elapsed: timeline.date.timeIntervalSince(startedAt),
                        reduceMotion: false
                    ))
                }
            }
        }
        .onAppear { startedAt = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("言いよどんでいる")
    }

    private func bubble(visibleDotCount: Int) -> some View {
        ZStack(alignment: .top) {
            ADVHesitationBubbleShape()
                .fill(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 7, y: 3)

            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(AppColor.primary.opacity(index < visibleDotCount ? 1 : 0.22))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(height: 45)
        }
    }
}

private struct ADVHesitationBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - 11
        ), cornerRadius: 18)
        path.move(to: CGPoint(x: rect.minX + 22, y: rect.maxY - 14))
        path.addLine(to: CGPoint(x: rect.minX + 15, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 38, y: rect.maxY - 11))
        path.closeSubpath()
        return path
    }
}

enum ADVPlaybackMode: String, Equatable {
    case manual
    case auto
    case fastForward
}

enum ADVPlaybackTiming {
    static let typingIntervalNanoseconds: UInt64 = 32_000_000
    static let fastAdvanceDelayNanoseconds: UInt64 = 140_000_000
    static let autoNonTextAdvanceDelayNanoseconds: UInt64 = 1_400_000_000

    static func autoAdvanceDelayNanoseconds(characterCount: Int) -> UInt64 {
        let readableCharacterCount = UInt64(max(0, min(characterCount, 54)))
        return min(2_800_000_000, 900_000_000 + readableCharacterCount * 35_000_000)
    }
}

private struct ADVPlaybackControlBar: View {
    let playbackMode: ADVPlaybackMode
    let isLogAvailable: Bool
    let isAutomationAvailable: Bool
    let isFastForwardEnabled: Bool
    let allowsSkip: Bool
    let onSkip: () -> Void
    let onClose: () -> Void
    let onShowLog: () -> Void
    let onToggleAuto: () -> Void
    let onToggleFastForward: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            controlButton(
                title: allowsSkip ? "スキップ" : "閉じる",
                symbol: allowsSkip ? "forward.end.fill" : "xmark",
                action: allowsSkip ? onSkip : onClose
            )
            controlButton(
                title: "ログ",
                symbol: "list.bullet.rectangle",
                isEnabled: isLogAvailable,
                action: onShowLog
            )
            controlButton(
                title: "オート",
                symbol: "play.fill",
                isActive: playbackMode == .auto,
                reportsActiveState: true,
                isEnabled: isAutomationAvailable,
                action: onToggleAuto
            )
            controlButton(
                title: "早送り",
                symbol: "forward.fill",
                isActive: playbackMode == .fastForward,
                reportsActiveState: true,
                isEnabled: isAutomationAvailable && isFastForwardEnabled,
                action: onToggleFastForward
            )
        }
        .padding(5)
        .frame(height: 56)
        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ADV操作メニュー")
    }

    private func controlButton(
        title: String,
        symbol: String,
        isActive: Bool = false,
        reportsActiveState: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.primary.opacity(0.88))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityValue(reportsActiveState ? (isActive ? "オン" : "オフ") : "")
    }
}

private struct ADVAdvanceIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -2

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption.bold())
            .foregroundStyle(AppColor.primary)
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

struct ADVTextWindow: View {
    let node: StoryNode
    let maxWidth: CGFloat
    let horizontalPadding: CGFloat
    let onAdvance: ((StoryAdvancePace) -> Void)?
    var onTextWindowTap: () -> Void = {}
    var backgroundStyle: ADVTextWindowBackgroundStyle = .material
    var playbackMode: ADVPlaybackMode = .manual
    var isPlaybackPaused = false
    var isAutomationAvailable = true
    var isTextRevealEnabled = true
    var isTypingEffectEnabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex = 0
    @State private var revealedCharacterCount = 0

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

    private var displayPages: [String] {
        ADVTextLayout.pages(node.storyDisplayText)
    }

    private var currentPageIndex: Int {
        min(pageIndex, max(0, displayPages.count - 1))
    }

    private var currentPage: String {
        displayPages[currentPageIndex]
    }

    private var revealedText: String {
        guard isTextRevealEnabled else { return "" }
        if revealsImmediately { return currentPage }
        return String(currentPage.prefix(revealedCharacterCount))
    }

    private var isPageFullyRevealed: Bool {
        isTextRevealEnabled
            && (revealsImmediately || revealedCharacterCount >= currentPage.count)
    }

    private var revealsImmediately: Bool {
        !isTypingEffectEnabled || reduceMotion || playbackMode == .fastForward
    }

    private var hasNextPage: Bool {
        currentPageIndex + 1 < displayPages.count
    }

    private var canRespondToTap: Bool {
        isTextRevealEnabled
            && !isPlaybackPaused
            && (hasNextPage || onAdvance != nil || !isPageFullyRevealed)
    }

    private var showsAdvanceIndicator: Bool {
        isTextRevealEnabled
            && isPageFullyRevealed
            && !isPlaybackPaused
            && (hasNextPage || onAdvance != nil)
    }

    private var revealTaskID: String {
        [
            node.nodeId,
            String(currentPageIndex),
            playbackMode.rawValue,
            String(isPlaybackPaused),
            String(isTypingEffectEnabled),
            String(isTextRevealEnabled),
            String(reduceMotion),
        ].joined(separator: "|")
    }

    private var automaticContinuationTaskID: String {
        [
            node.nodeId,
            String(currentPageIndex),
            String(isPageFullyRevealed),
            playbackMode.rawValue,
            String(isPlaybackPaused),
            String(isAutomationAvailable),
            String(isTextRevealEnabled),
        ].joined(separator: "|")
    }

    private var windowBorderOpacity: Double {
        switch backgroundStyle {
        case .material:
            return 0.9
        case .baseColor:
            return 0.75
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { proxy in
                let textWidth = max(0, proxy.size.width - horizontalPadding * 2)

                Text(revealedText)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // Material alone inherits too much of a dark scene's hue.
                    // Keep the blur, then anchor the window to a translucent
                    // white base so dark backgrounds cannot reduce legibility.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColor.surface.opacity(0.84))
                }
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            case .baseColor:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.background)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(windowBorderOpacity), lineWidth: 1)
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
                    .offset(y: -19)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsAdvanceIndicator {
                ADVAdvanceIndicator()
                    .padding(.trailing, 18)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            handleTap()
        }
        .task(id: revealTaskID) {
            await revealCurrentPage()
        }
        .task(id: automaticContinuationTaskID) {
            await automaticallyContinueIfNeeded()
        }
        .onChange(of: node.nodeId) { _, _ in
            pageIndex = 0
            revealedCharacterCount = 0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(canRespondToTap ? .isButton : [])
        .accessibilityHint(accessibilityHint)
        .accessibilityHidden(!isTextRevealEnabled || isPlaybackPaused)
    }

    private var accessibilityText: String {
        if let displaySpeakerName {
            return "\(displaySpeakerName)、\(currentPage)"
        }
        return currentPage
    }

    private var accessibilityHint: String {
        guard canRespondToTap else { return "" }
        if !isPageFullyRevealed { return "ダブルタップして全文を表示します" }
        return hasNextPage
            ? "ダブルタップして続きの文章を表示します"
            : "ダブルタップして次へ進みます"
    }

    private func handleTap() {
        guard canRespondToTap else { return }
        onTextWindowTap()
        if !isPageFullyRevealed {
            revealedCharacterCount = currentPage.count
            return
        }
        continueAfterCurrentPage()
    }

    private func continueAfterCurrentPage() {
        if hasNextPage {
            pageIndex = currentPageIndex + 1
            revealedCharacterCount = 0
        } else {
            onAdvance?(playbackMode == .fastForward ? .fastForward : .normal)
        }
    }

    private func revealCurrentPage() async {
        guard isTextRevealEnabled, !isPlaybackPaused else { return }
        let characterCount = currentPage.count

        guard !revealsImmediately else {
            revealedCharacterCount = characterCount
            return
        }

        while revealedCharacterCount < characterCount {
            revealedCharacterCount += 1
            guard revealedCharacterCount < characterCount else { return }

            do {
                try await Task<Never, Never>.sleep(
                    nanoseconds: ADVPlaybackTiming.typingIntervalNanoseconds
                )
            } catch {
                return
            }
            guard !Task.isCancelled,
                  isTextRevealEnabled,
                  !isPlaybackPaused else { return }
        }
    }

    private func automaticallyContinueIfNeeded() async {
        guard isPageFullyRevealed,
              isTextRevealEnabled,
              !isPlaybackPaused,
              isAutomationAvailable,
              playbackMode != .manual,
              hasNextPage || onAdvance != nil else {
            return
        }

        let delay = playbackMode == .fastForward
            ? ADVPlaybackTiming.fastAdvanceDelayNanoseconds
            : ADVPlaybackTiming.autoAdvanceDelayNanoseconds(
                characterCount: currentPage.count
            )
        do {
            try await Task<Never, Never>.sleep(nanoseconds: delay)
        } catch {
            return
        }
        guard !Task.isCancelled, !isPlaybackPaused else { return }
        continueAfterCurrentPage()
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
            .replacingOccurrences(of: "[sp]", with: " ")

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap(wrappedLines)
            .joined(separator: "\n")
    }

    /// 1ページを最大3行に分け、長い既存セリフも欠落させず順番に表示する。
    static func pages(_ source: String) -> [String] {
        let lines = formatted(source)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard !lines.isEmpty else { return [""] }

        return stride(from: 0, to: lines.count, by: maximumLines).map { start in
            let end = min(start + maximumLines, lines.count)
            return lines[start..<end].joined(separator: "\n")
        }
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
