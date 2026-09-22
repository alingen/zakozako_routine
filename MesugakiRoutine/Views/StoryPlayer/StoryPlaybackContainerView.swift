import AVFoundation
import SwiftData
import SwiftUI

@MainActor
private final class StoryBGMPlaybackController: ObservableObject {
    private var player: AVAudioPlayer?
    private var currentState: StoryBGMPlaybackState?

    func synchronize(with state: StoryBGMPlaybackState?) {
        guard state != currentState else { return }
        stop()
        guard let state, let url = audioURL(for: state.assetID) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = state.loop ? -1 : 0
            player.volume = state.fadeMilliseconds > 0 ? 0 : state.volume
            player.prepareToPlay()
            guard player.play() else { return }
            if state.fadeMilliseconds > 0 {
                player.setVolume(
                    state.volume,
                    fadeDuration: TimeInterval(state.fadeMilliseconds) / 1_000
                )
            }
            self.player = player
            currentState = state
        } catch {
            player = nil
            currentState = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentState = nil
    }

    private func audioURL(for assetID: String) -> URL? {
        if let exact = Bundle.main.url(forResource: assetID, withExtension: nil) {
            return exact
        }
        for fileExtension in ["m4a", "mp3", "wav", "caf", "aac"] {
            if let matched = Bundle.main.url(forResource: assetID, withExtension: fileExtension) {
                return matched
            }
        }
        return nil
    }
}

enum ADVOpeningRevealPhase: Int, Equatable {
    case blackout
    case scene
    case textBox
    case text

    var showsScene: Bool { rawValue >= Self.scene.rawValue }
    var showsTextBox: Bool { rawValue >= Self.textBox.rawValue }
    var startsTextReveal: Bool { rawValue >= Self.text.rawValue }
}

enum ADVOpeningRevealTiming {
    static let blackoutNanoseconds: UInt64 = 300_000_000
    static let sceneToTextBoxNanoseconds: UInt64 = 300_000_000
    static let textBoxToTextNanoseconds: UInt64 = 200_000_000

    static let sceneStartNanoseconds = blackoutNanoseconds
    static let textBoxStartNanoseconds = sceneStartNanoseconds
        + sceneToTextBoxNanoseconds
    static let textStartNanoseconds = textBoxStartNanoseconds
        + textBoxToTextNanoseconds

    static func initialPhase(hasEventTitle: Bool) -> ADVOpeningRevealPhase {
        hasEventTitle ? .blackout : .text
    }

    static func phase(atElapsedNanoseconds elapsed: UInt64) -> ADVOpeningRevealPhase {
        if elapsed < sceneStartNanoseconds { return .blackout }
        if elapsed < textBoxStartNanoseconds { return .scene }
        if elapsed < textStartNanoseconds { return .textBox }
        return .text
    }
}

/// SwiftUIのライフサイクルとUI非依存の`StoryPlayer`を接続する薄いcontainer。
@MainActor
struct StoryPlaybackContainerView: View {
    @Environment(\.modelContext) private var modelContext

    let launch: StoryLaunchRequest
    let onClose: () -> Void

    @State private var player: StoryPlayer?
    @State private var preparationError: String?
    @State private var isShowingEventTitleIntro = false
    @State private var isEventTitleIntroVisible = false
    @State private var advOpeningRevealPhase: ADVOpeningRevealPhase = .text
    @State private var lastActiveSnapshot: StoryPlayerViewSnapshot?
    @State private var isCompletionFadeVisible = false
    @StateObject private var bgmPlayback = StoryBGMPlaybackController()

    var body: some View {
        ZStack {
            Group {
                if let player {
                    let liveInput = snapshot(of: player)
                    let renderedInput = displayedSnapshot(from: liveInput)
                    StoryPlayerView(
                        input: renderedInput,
                        advOpeningRevealPhase: advOpeningRevealPhase,
                        onAdvance: { pace in
                            Task {
                                await player.advance(
                                    expectedNodeId: liveInput.currentNode?.nodeId,
                                    pace: pace
                                )
                            }
                        },
                        onChoice: { choice in
                            Task {
                                await player.selectChoice(
                                    choice,
                                    expectedNodeId: liveInput.currentNode?.nodeId
                                )
                            }
                        },
                        onDismissModal: {
                            Task {
                                await player.dismissModal(
                                    expectedNodeId: liveInput.currentNode?.nodeId
                                )
                            }
                        },
                        onPresentNode: {
                            player.markCurrentNodePresented(
                                expectedNodeId: liveInput.currentNode?.nodeId
                            )
                        },
                        onSkip: {
                            Task {
                                if await player.skip() {
                                    onClose()
                                }
                            }
                        },
                        onClose: {
                            player.close()
                            onClose()
                        }
                    )
                    .onAppear {
                        cacheActiveSnapshot(liveInput)
                    }
                    .onChange(of: presentationCacheKey(for: liveInput)) { _, _ in
                        cacheActiveSnapshot(liveInput)
                    }
                } else if let preparationError {
                    unavailableView(message: preparationError)
                } else {
                    ProgressView("ストーリーを読み込み中…")
                        .tint(AppColor.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColor.background)
                }
            }

            if advOpeningRevealPhase == .blackout {
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(9)
                    .accessibilityHidden(true)
            }

            if isShowingEventTitleIntro {
                StoryEventTitleIntroView(
                    title: launch.title,
                    isVisible: isEventTitleIntroVisible
                )
                .zIndex(10)
            }

            if shouldRunCompletionFade {
                Color.black
                    .opacity(isCompletionFadeVisible ? 1 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(20)
                    .accessibilityHidden(true)
            }
        }
        .task(id: launch.id) {
            await prepare()
        }
        .onAppear {
            updateOrientationForStory()
        }
        .onChange(of: usesLandscapePresentation) { _, _ in
            updateOrientationForStory()
        }
        .task(id: shouldRunCompletionFade) {
            await runCompletionFadeIfNeeded()
        }
        .onChange(of: player?.bgmPlaybackState) { _, state in
            bgmPlayback.synchronize(with: state)
        }
        .onDisappear {
            player?.close()
            bgmPlayback.stop()
            AppOrientationController.set(.portrait)
        }
    }

    private var usesLandscapePresentation: Bool {
        StoryPresentationOrientationPolicy.usesLandscape(
            scenarioType: launch.scenario.scenarioType,
            cgAssetID: player?.cgAssetID,
            isCompleted: player?.isCompleted == true
        )
    }

    private var shouldRunCompletionFade: Bool {
        player?.isCompleted == true
            && StoryCompletionPresentationPolicy.returnsToMenuAutomatically(
                after: launch.scenario.scenarioType
            )
    }

    private func updateOrientationForStory() {
        AppOrientationController.set(usesLandscapePresentation ? .landscape : .portrait)
    }

    private func prepare() async {
        player?.close()
        bgmPlayback.stop()
        player = nil
        preparationError = nil
        isShowingEventTitleIntro = false
        isEventTitleIntroVisible = false
        advOpeningRevealPhase = ADVOpeningRevealTiming.initialPhase(
            hasEventTitle: launch.event != nil
        )
        lastActiveSnapshot = nil
        isCompletionFadeVisible = false

        do {
            let content = try StoryContentRepository()
            let state = StoryStateRepository(context: modelContext)
            let created = StoryPlayer(
                scenario: launch.scenario,
                event: launch.event,
                playbackKey: launch.playbackKey,
                contentRepository: content,
                stateRepository: state
            )
            player = created

            if launch.event != nil {
                await presentEventTitleIntro(starting: created)
            } else {
                await created.start()
            }
        } catch {
            preparationError = error.localizedDescription
        }
    }

    private func presentEventTitleIntro(starting player: StoryPlayer) async {
        isShowingEventTitleIntro = true
        isEventTitleIntroVisible = false
        async let playerStart: Void = player.start()

        try? await Task<Never, Never>.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.32)) {
            isEventTitleIntroVisible = true
        }

        try? await Task<Never, Never>.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }

        // The title stays on an opaque black screen until the first story node
        // is ready. This prevents a slow restore or an opening wait command
        // from leaving the staged ADV reveal without scene content.
        await playerStart
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.3)) {
            isEventTitleIntroVisible = false
        }

        try? await Task<Never, Never>.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        let shouldStageADVReveal = player.currentMode == .adv
        if !shouldStageADVReveal {
            // Chat/call events keep their existing immediate presentation once
            // the opaque title screen is gone. The staged reveal is ADV-only.
            advOpeningRevealPhase = .text
        }
        isShowingEventTitleIntro = false

        if shouldStageADVReveal {
            await revealADVAfterEventTitle()
        }
    }

    private func revealADVAfterEventTitle() async {
        do {
            try await Task<Never, Never>.sleep(
                nanoseconds: ADVOpeningRevealTiming.blackoutNanoseconds
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        advOpeningRevealPhase = .scene

        do {
            try await Task<Never, Never>.sleep(
                nanoseconds: ADVOpeningRevealTiming.sceneToTextBoxNanoseconds
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        advOpeningRevealPhase = .textBox

        do {
            try await Task<Never, Never>.sleep(
                nanoseconds: ADVOpeningRevealTiming.textBoxToTextNanoseconds
            )
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        advOpeningRevealPhase = .text
    }

    private func snapshot(of player: StoryPlayer) -> StoryPlayerViewSnapshot {
        StoryPlayerViewSnapshot(
            title: launch.title,
            scenarioType: launch.scenario.scenarioType,
            currentNode: player.currentNode,
            currentMode: player.currentMode,
            visibleChatNodes: player.visibleChatNodes,
            visibleLogNodes: player.visibleLogNodes,
            backgroundAssetID: player.backgroundAssetID,
            portraitAssetID: player.portraitAssetID,
            cgAssetID: player.cgAssetID,
            availableChoices: player.availableChoices,
            isTyping: player.isTyping,
            isModalPresented: player.isModalPresented,
            isCompleted: player.isCompleted,
            isCurrentNodeTerminal: player.isCurrentNodeTerminal,
            recoverableError: player.recoverableError
        )
    }

    private func displayedSnapshot(
        from liveInput: StoryPlayerViewSnapshot
    ) -> StoryPlayerViewSnapshot {
        guard shouldRunCompletionFade, let lastActiveSnapshot else {
            return liveInput
        }
        return lastActiveSnapshot
    }

    private func cacheActiveSnapshot(_ snapshot: StoryPlayerViewSnapshot) {
        guard !snapshot.isCompleted, snapshot.currentNode != nil else { return }
        lastActiveSnapshot = snapshot
    }

    private func presentationCacheKey(
        for snapshot: StoryPlayerViewSnapshot
    ) -> String {
        [
            snapshot.currentNode?.nodeId ?? "",
            snapshot.currentMode.rawValue,
            String(snapshot.visibleChatNodes.count),
            String(snapshot.visibleLogNodes.count),
            String(snapshot.availableChoices.count),
            String(snapshot.isTyping),
            String(snapshot.isModalPresented),
        ].joined(separator: "|")
    }

    private func runCompletionFadeIfNeeded() async {
        guard shouldRunCompletionFade else {
            isCompletionFadeVisible = false
            return
        }

        do {
            try await Task<Never, Never>.sleep(nanoseconds: 40_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, shouldRunCompletionFade else { return }

        withAnimation(.easeIn(duration: 0.35)) {
            isCompletionFadeVisible = true
        }

        do {
            try await Task<Never, Never>.sleep(nanoseconds: 400_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled, shouldRunCompletionFade else { return }

        player?.close()
        onClose()
    }

    private func unavailableView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppColor.warning)
            Text("ストーリーを開始できませんでした")
                .font(.headline)
                .foregroundStyle(AppColor.text)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
            Button("閉じる", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
    }
}

private struct StoryEventTitleIntroView: View {
    let title: String
    let isVisible: Bool

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ZStack {
                LinearGradient(
                    colors: [
                        AppColor.secondary.opacity(0.82),
                        AppColor.secondary,
                        AppColor.secondary.opacity(0.82),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.34))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(.white.opacity(0.34))
                        .frame(height: 1)
                }

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .scaleEffect(x: isVisible ? 1 : 0.78, y: 1, anchor: .center)
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible ? 0 : 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("イベントタイトル。\(title)")
    }
}

extension StoryScenarioType {
    var supportsLandscapeStillPresentation: Bool {
        switch self {
        case .prologue, .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}

enum StoryPresentationOrientationPolicy {
    static func usesLandscape(
        scenarioType: StoryScenarioType,
        cgAssetID: String?,
        isCompleted: Bool
    ) -> Bool {
        guard scenarioType.supportsLandscapeStillPresentation,
              !isCompleted,
              let cgAssetID,
              !cgAssetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }
}

enum StoryCompletionPresentationPolicy {
    static func returnsToMenuAutomatically(after scenarioType: StoryScenarioType) -> Bool {
        switch scenarioType {
        case .prologue, .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}

enum StoryLogPresentationPolicy {
    static func isAvailable(for scenarioType: StoryScenarioType) -> Bool {
        switch scenarioType {
        case .prologue, .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}
