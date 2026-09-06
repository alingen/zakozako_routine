import SwiftData
import SwiftUI

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
    @State private var lastActiveSnapshot: StoryPlayerViewSnapshot?
    @State private var isCompletionFadeVisible = false

    var body: some View {
        ZStack {
            Group {
                if let player {
                    let liveInput = snapshot(of: player)
                    let renderedInput = displayedSnapshot(from: liveInput)
                    StoryPlayerView(
                        input: renderedInput,
                        onAdvance: {
                            Task {
                                await player.advance(
                                    expectedNodeId: liveInput.currentNode?.nodeId
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
                        onRestart: {
                            Task { await player.restart() }
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
        .onDisappear {
            player?.close()
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
        player = nil
        preparationError = nil
        isShowingEventTitleIntro = false
        isEventTitleIntroVisible = false
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
            let startTask = Task { await created.start() }

            if launch.event != nil {
                await presentEventTitleIntro()
            }

            await startTask.value
        } catch {
            preparationError = error.localizedDescription
        }
    }

    private func presentEventTitleIntro() async {
        isShowingEventTitleIntro = true
        isEventTitleIntroVisible = false

        try? await Task<Never, Never>.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.32)) {
            isEventTitleIntroVisible = true
        }

        try? await Task<Never, Never>.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.3)) {
            isEventTitleIntroVisible = false
        }

        try? await Task<Never, Never>.sleep(nanoseconds: 320_000_000)
        guard !Task.isCancelled else { return }
        isShowingEventTitleIntro = false
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
                .opacity(isVisible ? 0.58 : 0)
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
        case .middleEvent, .largeEvent:
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
        case .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}

enum StoryLogPresentationPolicy {
    static func isAvailable(for scenarioType: StoryScenarioType) -> Bool {
        switch scenarioType {
        case .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}
