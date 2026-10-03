import AVFoundation
import SwiftData
import SwiftUI

@MainActor
protocol StoryBGMAudioPlayer: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func setVolume(_ volume: Float, fadeDuration duration: TimeInterval)
    func stop()
}

extension AVAudioPlayer: StoryBGMAudioPlayer {}

@MainActor
final class StoryBGMPlaybackController: ObservableObject {
    private var player: (any StoryBGMAudioPlayer)?
    private var currentState: StoryBGMPlaybackState?
    private var fadingPlayers: [UUID: (player: any StoryBGMAudioPlayer, task: Task<Void, Never>)] = [:]
    private let makePlayer: (String) throws -> (any StoryBGMAudioPlayer)?
    private let configureAudioSession: () throws -> Void
    private let sleep: StoryPlayerSleep

    init(
        makePlayer: @escaping (String) throws -> (any StoryBGMAudioPlayer)? = { assetID in
            guard let url = storyAudioURL(for: assetID) else { return nil }
            return try AVAudioPlayer(contentsOf: url)
        },
        configureAudioSession: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        },
        sleep: @escaping StoryPlayerSleep = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    ) {
        self.makePlayer = makePlayer
        self.configureAudioSession = configureAudioSession
        self.sleep = sleep
    }

    func synchronize(with update: StoryBGMPlaybackUpdate) {
        if update.events.isEmpty {
            // Restoring a checkpoint starts only its final BGM, not past audio commands.
            guard update.state != currentState else { return }
            if let state = update.state { play(state) } else { stop() }
        } else {
            for event in update.events {
                switch event {
                case .play(let state): play(state)
                case .stop(let fadeMilliseconds): stop(fadeMilliseconds: fadeMilliseconds)
                }
            }
        }
    }

    private func play(_ state: StoryBGMPlaybackState) {
        guard state != currentState else { return }
        stop()

        do {
            try configureAudioSession()
            guard let player = try makePlayer(state.assetID) else { return }
            player.numberOfLoops = state.loop ? -1 : 0
            player.volume = state.fadeMilliseconds > 0 ? 0 : state.volume
            _ = player.prepareToPlay()
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

    func stop(fadeMilliseconds: UInt64 = StoryBGMPlaybackState.defaultStopFadeMilliseconds) {
        let outgoing = player
        player = nil
        currentState = nil

        if fadeMilliseconds == 0 {
            outgoing?.stop()
            for fade in fadingPlayers.values {
                fade.task.cancel()
                fade.player.stop()
            }
            fadingPlayers.removeAll()
            return
        }

        // Repeated cleanup calls must not restart an already-running fade.
        guard let outgoing else { return }
        outgoing.setVolume(0, fadeDuration: TimeInterval(fadeMilliseconds) / 1_000)
        let id = UUID()
        let sleep = sleep
        let task = Task { @MainActor [weak self] in
            do { try await sleep(fadeMilliseconds) } catch { }
            guard !Task.isCancelled else { return }
            // Retain this specific player through view dismissal. Never stop a newer track.
            outgoing.stop()
            self?.fadingPlayers.removeValue(forKey: id)
        }
        fadingPlayers[id] = (outgoing, task)
    }
}

@MainActor
protocol StorySoundEffectAudioPlayer: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

extension AVAudioPlayer: StorySoundEffectAudioPlayer {}

@MainActor
final class StorySoundEffectPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var players: [(assetID: String, player: any StorySoundEffectAudioPlayer)] = []
    private var loopingPlayers: [String: any StorySoundEffectAudioPlayer] = [:]
    private var textWindowClickPlayer: AVAudioPlayer?
    private let makePlayer: (String) throws -> (any StorySoundEffectAudioPlayer)?
    private let configureAudioSession: () throws -> Void

    init(
        makePlayer: @escaping (String) throws -> (any StorySoundEffectAudioPlayer)? = { assetID in
            guard let url = storyAudioURL(for: assetID) else { return nil }
            return try AVAudioPlayer(contentsOf: url)
        },
        configureAudioSession: @escaping () throws -> Void = {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        }
    ) {
        self.makePlayer = makePlayer
        self.configureAudioSession = configureAudioSession
        super.init()
    }

    func playTextWindowClick() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            if textWindowClickPlayer == nil {
                guard let url = storyAudioURL(for: "se_click") else { return }
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 0.22
                player.prepareToPlay()
                textWindowClickPlayer = player
            }
            // A second tap restarts the same sound instead of layering another copy.
            textWindowClickPlayer?.stop()
            textWindowClickPlayer?.currentTime = 0
            textWindowClickPlayer?.play()
        } catch {
            textWindowClickPlayer = nil
        }
    }

    func play(_ events: [StorySoundEffectEvent]) {
        for event in events {
            switch event {
            case .stop(let assetID):
                // Stop every overlapping one-shot of this asset, but leave other sounds alone.
                // Loops are controlled by synchronizeLooping, not this transient queue.
                for entry in players where entry.assetID == assetID {
                    entry.player.stop()
                }
                players.removeAll { $0.assetID == assetID }
            case .play(let effect):
                do {
                    try configureAudioSession()
                    guard let player = try makePlayer(effect.assetID) else { continue }
                    player.volume = effect.volume
                    (player as? AVAudioPlayer)?.delegate = self
                    _ = player.prepareToPlay()
                    if player.play() {
                        players.append((effect.assetID, player))
                    }
                } catch {
                    // A failed play must not discard a later stop in the same batch.
                    continue
                }
            }
        }
    }

    func synchronizeLooping(with effects: [String: StorySoundEffectPlayback]) {
        let staleAssetIDs = loopingPlayers.keys.filter { effects[$0] == nil }
        for assetID in staleAssetIDs {
            loopingPlayers.removeValue(forKey: assetID)?.stop()
        }
        guard !effects.isEmpty else { return }
        do {
            try configureAudioSession()
        } catch {
            return
        }

        for (assetID, effect) in effects {
            if let player = loopingPlayers[assetID] {
                player.volume = effect.volume
                if !player.isPlaying {
                    player.currentTime = 0
                    player.play()
                }
                continue
            }
            do {
                guard let player = try makePlayer(assetID) else { continue }
                player.numberOfLoops = -1
                player.volume = effect.volume
                _ = player.prepareToPlay()
                if player.play() {
                    loopingPlayers[assetID] = player
                }
            } catch {
                continue
            }
        }
    }

    func stop() {
        players.forEach { $0.player.stop() }
        players = []
        loopingPlayers.values.forEach { $0.stop() }
        loopingPlayers = [:]
        textWindowClickPlayer?.stop()
        textWindowClickPlayer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.players.removeAll { $0.player === player }
        }
    }
}

private func storyAudioURL(for assetID: String) -> URL? {
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
    static let sceneFadeSeconds = 0.25
    static let sceneToTextBoxNanoseconds: UInt64 = 300_000_000
    static let textBoxToTextNanoseconds: UInt64 = 200_000_000

    static let textBoxStartNanoseconds = sceneToTextBoxNanoseconds
    static let textStartNanoseconds = textBoxStartNanoseconds
        + textBoxToTextNanoseconds

    static func initialPhase(hasEventTitle: Bool) -> ADVOpeningRevealPhase {
        hasEventTitle ? .blackout : .text
    }

    static func phase(atElapsedNanoseconds elapsed: UInt64) -> ADVOpeningRevealPhase {
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
    var allowsSkip = true
    let onClose: () -> Void

    @State private var player: StoryPlayer?
    @State private var preparationError: String?
    @State private var isShowingEventTitleIntro = false
    @State private var isEventTitleIntroVisible = false
    @State private var advOpeningRevealPhase: ADVOpeningRevealPhase = .text
    @State private var lastActiveSnapshot: StoryPlayerViewSnapshot?
    @State private var isCompletionFadeVisible = false
    @StateObject private var bgmPlayback = StoryBGMPlaybackController()
    @StateObject private var soundEffectPlayback = StorySoundEffectPlaybackController()
    #if DEBUG
    @State private var transitionDiagnostics = StoryTransitionFrameDiagnostics()
    #endif

    var body: some View {
        ZStack {
            Group {
                if let player {
                    let liveInput = snapshot(of: player)
                    let renderedInput = displayedSnapshot(from: liveInput)
                    StoryPlayerView(
                        input: renderedInput,
                        advOpeningRevealPhase: advOpeningRevealPhase,
                        allowsSkip: allowsSkip,
                        isSceneTransitionActive: player.sceneTransition != nil,
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
                            guard allowsSkip else { return }
                            Task {
                                if await player.skip() {
                                    onClose()
                                }
                            }
                        },
                        onClose: {
                            player.close()
                            onClose()
                        },
                        onTextWindowTap: {
                            soundEffectPlayback.playTextWindowClick()
                        }
                    )
                    .allowsHitTesting(player.sceneTransition == nil)
                    .accessibilityHidden(player.sceneTransition != nil)
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

            Color.black
                .opacity(advOpeningRevealPhase == .blackout ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(advOpeningRevealPhase == .blackout)
                .zIndex(9)
                .accessibilityHidden(true)

            if isShowingEventTitleIntro {
                StoryEventTitleIntroView(
                    title: launch.title,
                    isVisible: isEventTitleIntroVisible
                )
                .transition(.identity)
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

            if let transition = player?.sceneTransition {
                StorySceneTransitionOverlay(state: transition)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .zIndex(30)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("場面転換中")
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
        .task(id: shouldRunCompletionFade && player?.sceneTransition == nil) {
            await runCompletionFadeIfNeeded()
        }
        .onChange(of: player?.bgmPlaybackUpdate, initial: true) { _, _ in
            synchronizeBGMAudio()
        }
        .onChange(of: player?.loopingSoundEffects, initial: true) { _, effects in
            soundEffectPlayback.synchronizeLooping(with: effects ?? [:])
        }
        .onChange(of: player?.pendingSoundEffects, initial: true) { _, _ in
            if let player {
                soundEffectPlayback.play(player.consumePendingSoundEffects())
            }
        }
        .onDisappear {
            #if DEBUG
            transitionDiagnostics.update(isActive: false)
            #endif
            synchronizeBGMAudio()
            player?.close()
            bgmPlayback.stop()
            soundEffectPlayback.stop()
            AppOrientationController.set(.portrait)
        }
        #if DEBUG
        .onChange(of: player?.sceneTransition != nil) { _, active in
            transitionDiagnostics.update(isActive: active)
        }
        .task(id: player != nil) {
            guard launch.scenario.scenarioId == "debug_color_slide",
                  ProcessInfo.processInfo.arguments.contains("--color-slide-autoplay"),
                  let player else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await player.advance()
            }
        }
        #endif
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

    private func synchronizeBGMAudio() {
        guard let player else { return }
        bgmPlayback.synchronize(with: StoryBGMPlaybackUpdate(
            state: player.bgmPlaybackState,
            events: player.consumePendingBGMEvents()
        ))
    }

    private func prepare() async {
        synchronizeBGMAudio()
        player?.close()
        bgmPlayback.stop()
        soundEffectPlayback.stop()
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
                stateRepository: state,
                preloadSceneAssets: { ids in
                    #if DEBUG
                    if launch.scenario.scenarioId == "debug_color_slide",
                       ProcessInfo.processInfo.arguments.contains("--color-slide-slow-assets") {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    }
                    #endif
                    await StorySceneAssetPreparation.shared.prepare(ids)
                },
                transitionFrameBarrier: { await awaitStoryRenderedFrame() },
                reduceMotion: {
                    #if DEBUG
                    if launch.scenario.scenarioId == "debug_color_slide",
                       ProcessInfo.processInfo.arguments.contains("--color-slide-reduce-motion") {
                        return true
                    }
                    #endif
                    return UIAccessibility.isReduceMotionEnabled
                }
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
        if shouldStageADVReveal {
            withAnimation(.easeOut(duration: ADVOpeningRevealTiming.sceneFadeSeconds)) {
                isShowingEventTitleIntro = false
                advOpeningRevealPhase = .scene
            }
            await revealADVAfterEventTitle()
        } else {
            isShowingEventTitleIntro = false
            advOpeningRevealPhase = .text
        }
    }

    private func revealADVAfterEventTitle() async {
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
            shouldDelayCurrentADVText: player.shouldDelayCurrentADVText,
            isHesitating: player.isHesitating,
            availableChoices: player.availableChoices,
            isTyping: player.isTyping,
            isWaitingForChatExit: player.isWaitingForChatExit,
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
            String(snapshot.isWaitingForChatExit),
            String(snapshot.isModalPresented),
        ].joined(separator: "|")
    }

    private func runCompletionFadeIfNeeded() async {
        guard shouldRunCompletionFade, player?.sceneTransition == nil else {
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
        // muted の補足文が読めるよう白地にする。
        .background(AppColor.surface)
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
