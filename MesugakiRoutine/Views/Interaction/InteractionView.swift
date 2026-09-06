import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InteractionViewModel()
    @State private var homeDialogueIndex: Int?

    private var homeDialogue: String? {
        guard let homeDialogueIndex,
              InteractionHomeDialogue.defaultLines.indices.contains(homeDialogueIndex) else {
            return nil
        }
        return InteractionHomeDialogue.defaultLines[homeDialogueIndex]
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = proxy.size.height + proxy.safeAreaInsets.bottom
            let backgroundHeight = visualHeight + proxy.safeAreaInsets.top

            ZStack(alignment: .top) {
                AppColor.background
                    .ignoresSafeArea()

                Image("rio_interaction_background")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: backgroundHeight,
                        alignment: .bottom
                    )
                    .clipped()
                    .offset(y: -proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .accessibilityHidden(true)

                Image("rio_interaction_home")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * 1.5)
                    .offset(y: 128)
                    .frame(
                        width: proxy.size.width,
                        height: visualHeight,
                        alignment: .top
                    )
                    .clipped()
                    .ignoresSafeArea(edges: .bottom)
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

                Button(action: showNextHomeDialogue) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(
                    width: proxy.size.width * 0.72,
                    height: proxy.size.height * 0.68
                )
                .position(
                    x: proxy.size.width * 0.46,
                    y: proxy.size.height * 0.55
                )
                .accessibilityLabel("莉央")
                .accessibilityHint("タップすると莉央が話します")

                if let homeDialogue {
                    InteractionCharacterSpeechBubble(text: homeDialogue)
                        .frame(width: min(300, proxy.size.width - 72))
                        .position(
                            x: proxy.size.width * 0.44,
                            y: proxy.size.height * 0.39
                        )
                        .id(homeDialogueIndex)
                        .transition(
                            .scale(scale: 0.92, anchor: .top)
                                .combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    if viewModel.showsTodayConversationCard {
                        TodayConversationCard(
                            title: viewModel.todayConversationTitle,
                            isUnread: viewModel.todayConversationIsUnread,
                            hasResumePosition: viewModel.todayConversationHasResumePosition,
                            isAvailable: viewModel.todayConversationIsAvailable,
                            action: { viewModel.openToday() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                    }

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
                    .padding(.bottom, 40)
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
            .frame(width: proxy.size.width, height: proxy.size.height)
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

    private func showNextHomeDialogue() {
        guard let nextIndex = InteractionHomeDialogue.nextIndex(after: homeDialogueIndex) else {
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            homeDialogueIndex = nextIndex
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
