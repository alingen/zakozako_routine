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

    var body: some View {
        ZStack {
            Group {
                if let player {
                    let renderedInput = snapshot(of: player)
                    StoryPlayerView(
                        input: renderedInput,
                        onAdvance: {
                            Task {
                                await player.advance(
                                    expectedNodeId: renderedInput.currentNode?.nodeId
                                )
                            }
                        },
                        onChoice: { choice in
                            Task {
                                await player.selectChoice(
                                    choice,
                                    expectedNodeId: renderedInput.currentNode?.nodeId
                                )
                            }
                        },
                        onDismissModal: {
                            Task {
                                await player.dismissModal(
                                    expectedNodeId: renderedInput.currentNode?.nodeId
                                )
                            }
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
        }
        .task(id: launch.id) {
            await prepare()
        }
        .onAppear {
            updateOrientationForStory()
        }
        .onDisappear {
            player?.close()
            if usesLandscapePresentation {
                AppOrientationController.set(.portrait)
            }
        }
    }

    private var usesLandscapePresentation: Bool {
        launch.scenario.scenarioType.usesLandscapeStoryPresentation
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
            backgroundAssetID: player.backgroundAssetID,
            portraitAssetID: player.portraitAssetID,
            cgAssetID: player.cgAssetID,
            availableChoices: player.availableChoices,
            isTyping: player.isTyping,
            isModalPresented: player.isModalPresented,
            isCompleted: player.isCompleted,
            recoverableError: player.recoverableError
        )
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
    var usesLandscapeStoryPresentation: Bool {
        switch self {
        case .middleEvent, .largeEvent:
            return true
        case .daily, .smallEvent, .unknown:
            return false
        }
    }
}
