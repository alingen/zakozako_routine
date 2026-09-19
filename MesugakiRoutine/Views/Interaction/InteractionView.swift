import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InteractionViewModel()

    private var homeDialogue: String? {
        viewModel.interactionComment?.text
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = proxy.size.height + proxy.safeAreaInsets.bottom
            let backgroundHeight = visualHeight + proxy.safeAreaInsets.top
            let artworkDrop = min(48, proxy.size.height * 0.055)
            let cardHeight = min(136, max(112, proxy.size.height * 0.18))

            ZStack(alignment: .top) {
                AppColor.background
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    Image("rio_interaction_background")
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: backgroundHeight,
                            alignment: .top
                        )
                        .offset(y: -proxy.safeAreaInsets.top + 60 )
                        .ignoresSafeArea(edges: .bottom)
                        .scaleEffect(1.2)

                    Image("rio_interaction_home")
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * 1.5)
                        .scaleEffect(1.2, anchor: .top)
                        .offset(y: 128 + artworkDrop)
                        .frame(
                            width: proxy.size.width,
                            height: visualHeight,
                            alignment: .top
                        )
                        .ignoresSafeArea(edges: .bottom)
                }
                .frame(width: proxy.size.width, height: visualHeight, alignment: .top)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

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
                    y: proxy.size.height * 0.55 + artworkDrop * 0.5
                )
                .accessibilityLabel("莉央")
                .accessibilityHint("タップすると莉央が話します")

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        InteractionProgressMiniCard(progress: viewModel.storyProgress)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, proxy.size.height * 0.10)

                    Spacer(minLength: 16)

                    if let homeDialogue {
                        InteractionCharacterSpeechBubble(text: homeDialogue, speakerName: "莉央")
                            .frame(width: min(340, proxy.size.width - 48))
                            .padding(.leading, 16)
                            .padding(.bottom, 20)
                            .id(viewModel.interactionComment?.id)
                            .transition(
                                .scale(scale: 0.94, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                            .allowsHitTesting(false)
                    }

                    InteractionHomeCardGrid {
                        todayCard(height: cardHeight)
                        storyCard(height: cardHeight)
                        memoriesCard(height: cardHeight)
                        freeTalkCard(height: cardHeight)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let loadError = viewModel.loadError {
                    VStack {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColor.warning)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
                            .padding(16)
                        Spacer()
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

    private func todayCard(height: CGFloat) -> some View {
        TodayConversationCard(
            title: viewModel.todayConversationTitle,
            isUnread: viewModel.todayConversationIsUnread,
            hasResumePosition: viewModel.todayConversationHasResumePosition,
            isAvailable: viewModel.todayConversationIsAvailable,
            height: height,
            action: { viewModel.openToday() }
        )
    }

    private func storyCard(height: CGFloat) -> some View {
        NavigationLink {
            StoryCatalogView(
                mainChapters: viewModel.mainChapters,
                subChapters: viewModel.subChapters,
                onOpen: viewModel.openEvent
            )
        } label: {
            InteractionHomeFeatureCard(
                kind: .story,
                title: "ストーリー",
                detail: "莉央との物語を読む",
                height: height
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("メインストーリーとサブストーリーを開きます")
    }

    private func memoriesCard(height: CGFloat) -> some View {
        NavigationLink {
            MemoryGalleryView(memories: viewModel.memories)
        } label: {
            InteractionHomeFeatureCard(
                kind: .memories,
                title: "思い出",
                detail: "あの時の莉央に会いに",
                height: height
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("思い出のコレクションを開きます")
    }

    private func freeTalkCard(height: CGFloat) -> some View {
        InteractionHomeFeatureCard(
            kind: .freeTalk,
            title: "ふりーとーく",
            detail: "",
            height: height
        )
        .allowsHitTesting(false)
    }

    private func showNextHomeDialogue() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            viewModel.selectInteractionComment(touchArea: "character")
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
