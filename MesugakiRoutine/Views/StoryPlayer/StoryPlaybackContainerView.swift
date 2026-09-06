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

    var body: some View {
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
        .task(id: launch.id) {
            await prepare()
        }
        .onDisappear {
            player?.close()
        }
    }

    private func prepare() async {
        player?.close()
        player = nil
        preparationError = nil

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
            await created.start()
        } catch {
            preparationError = error.localizedDescription
        }
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
