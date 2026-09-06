import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InteractionViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppColor.background
                    .ignoresSafeArea()

                Image("rio_interaction_home")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * 1.5)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        AppColor.background.opacity(0.44),
                        .clear,
                        AppColor.background.opacity(0.18),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    TodayConversationCard(
                        title: viewModel.todayConversationTitle,
                        isUnread: viewModel.todayConversationIsUnread,
                        hasResumePosition: viewModel.todayConversationHasResumePosition,
                        isAvailable: viewModel.todayConversationIsAvailable,
                        action: { viewModel.openToday() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    HStack {
                        Spacer(minLength: 0)

                        VStack(spacing: 12) {
                            NavigationLink {
                                StoryCatalogView(
                                    mainChapters: viewModel.mainChapters,
                                    subChapters: viewModel.subChapters,
                                    onOpen: viewModel.openEvent
                                )
                            } label: {
                                InteractionHomeDestinationButton(
                                    title: "ストーリー",
                                    systemImage: "book.pages.fill"
                                )
                            }

                            NavigationLink {
                                MemoryGalleryView(memories: viewModel.memories)
                            } label: {
                                InteractionHomeDestinationButton(
                                    title: "コレクション",
                                    systemImage: "photo.stack.fill"
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }

                if let loadError = viewModel.loadError {
                    VStack {
                        Spacer()
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColor.warning)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
                            .padding(16)
                    }
                }
            }
            .clipped()
        }
        .toolbar(.hidden, for: .navigationBar)
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
