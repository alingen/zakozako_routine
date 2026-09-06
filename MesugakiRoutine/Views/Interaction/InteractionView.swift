import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InteractionViewModel()

    private var storyCount: Int {
        (viewModel.mainChapters + viewModel.subChapters)
            .reduce(0) { $0 + $1.stories.count }
    }

    private var unlockedMemoryCount: Int {
        viewModel.memories.filter(\.isUnlocked).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                InteractionCharacterCard()

                sectionTitle("今日の会話")
                TodayConversationCard(
                    title: viewModel.todayConversationTitle,
                    detail: viewModel.todayConversationDetail,
                    hasResumePosition: viewModel.todayConversationHasResumePosition,
                    isAvailable: viewModel.todayConversationIsAvailable,
                    action: { viewModel.openToday() }
                )

                sectionTitle("コレクション")
                NavigationLink {
                    StoryCatalogView(
                        mainChapters: viewModel.mainChapters,
                        subChapters: viewModel.subChapters,
                        onOpen: viewModel.openEvent
                    )
                } label: {
                    InteractionDestinationCard(
                        title: "ストーリー",
                        detail: "メイン／サブ · \(storyCount)話",
                        systemImage: "book.pages.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MemoryGalleryView(memories: viewModel.memories)
                } label: {
                    InteractionDestinationCard(
                        title: "思い出",
                        detail: "\(unlockedMemoryCount) / \(viewModel.memories.count)枚 解放",
                        systemImage: "photo.stack.fill"
                    )
                }
                .buttonStyle(.plain)

                if let loadError = viewModel.loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColor.warning)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
        }
        .background(AppColor.background)
        .navigationTitle("交流")
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.reload() }
        }
        .fullScreenCover(
            item: Binding(
                get: { viewModel.activeLaunch },
                set: { if $0 == nil { viewModel.closePlayer() } }
            ),
            onDismiss: { viewModel.reload() }
        ) { launch in
            StoryPlaybackContainerView(launch: launch) {
                viewModel.closePlayer()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        InteractionView()
    }
    .modelContainer(
        for: [
            Routine.self,
            BlockedBehavior.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ],
        inMemory: true
    )
}
