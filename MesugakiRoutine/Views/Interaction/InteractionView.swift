import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InteractionViewModel()
    @State private var onboardingPlaybackKeyInPlayer: String?
    @State private var autoPlayedStoryEventID: String?

    @Binding private var openTodayConversationRequest: Bool
    @Binding private var openStoryEventRequest: String?
    private let onboardingConversationIdentity: OnboardingConversationIdentity?
    private let onOnboardingConversationPlaybackEnded: (Bool) -> Void
    private let onOnboardingConversationUnavailable: () -> Void
    private let onStoryEventAutoPlayEnded: (String, Bool) -> Void

    init(
        openTodayConversationRequest: Binding<Bool> = .constant(false),
        openStoryEventRequest: Binding<String?> = .constant(nil),
        onboardingConversationIdentity: OnboardingConversationIdentity? = nil,
        onOnboardingConversationPlaybackEnded: @escaping (Bool) -> Void = { _ in },
        onOnboardingConversationUnavailable: @escaping () -> Void = {},
        onStoryEventAutoPlayEnded: @escaping (String, Bool) -> Void = { _, _ in }
    ) {
        _openTodayConversationRequest = openTodayConversationRequest
        _openStoryEventRequest = openStoryEventRequest
        self.onboardingConversationIdentity = onboardingConversationIdentity
        self.onOnboardingConversationPlaybackEnded = onOnboardingConversationPlaybackEnded
        self.onOnboardingConversationUnavailable = onOnboardingConversationUnavailable
        self.onStoryEventAutoPlayEnded = onStoryEventAutoPlayEnded
    }

    private var homeDialogue: String? {
        viewModel.interactionComment?.text
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = proxy.size.height + proxy.safeAreaInsets.bottom
            let backgroundHeight = visualHeight + proxy.safeAreaInsets.top
            let artworkDrop = min(48, proxy.size.height * 0.055)

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
                        NavigationLink {
                            storyCatalog
                        } label: {
                            InteractionProgressMiniCard(progress: viewModel.storyProgress)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("ストーリーの一覧を開きます")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, proxy.size.height * 0.10)

                    Spacer(minLength: 16)

                    if let homeDialogue {
                        InteractionCharacterSpeechBubble(text: homeDialogue, speakerName: "莉央")
                            .frame(width: min(340, proxy.size.width - 48))
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                            .id(viewModel.interactionComment?.id)
                            .transition(
                                .scale(scale: 0.94, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                            .allowsHitTesting(false)
                    }

                    // 入口は1本のバーに3つだけ並べ、莉央の見える範囲を広く取る。
                    InteractionDock {
                        todayButton
                        storyButton
                        memoriesButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
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
        // バーは隠したまま、遷移先の戻るボタンに「交流」と出すためのタイトル。
        .navigationTitle("交流")
        .toolbar(.hidden, for: .navigationBar)
        // 立ち絵の上でもタブの文字が読めるよう、タブバーの地を常に敷く。
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            viewModel.configure(context: modelContext)
            offerDeferredConversationIfNeeded()
            openRequestedTodayConversationIfNeeded()
            openRequestedStoryEventIfNeeded()
        }
        .onAppear {
            viewModel.reload()
            offerDeferredConversationIfNeeded()
        }
        .onChange(of: onboardingConversationIdentity) { _, _ in
            viewModel.reload()
            offerDeferredConversationIfNeeded()
        }
        .onChange(of: openTodayConversationRequest) { _, requested in
            if requested { openRequestedTodayConversationIfNeeded() }
        }
        .onChange(of: openStoryEventRequest) { _, eventID in
            if eventID != nil { openRequestedStoryEventIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.reload()
                offerDeferredConversationIfNeeded()
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { viewModel.activeLaunch },
                set: { if $0 == nil { viewModel.closePlayer() } }
            ),
            onDismiss: {
                let playbackKey = onboardingPlaybackKeyInPlayer
                let didComplete = playbackKey.map(viewModel.isPlaybackCompleted) ?? false
                let autoPlayedEventID = autoPlayedStoryEventID
                let didCompleteAutoPlayedEvent = autoPlayedEventID.map {
                    viewModel.isPlaybackCompleted("event:\($0)")
                } ?? false
                onboardingPlaybackKeyInPlayer = nil
                autoPlayedStoryEventID = nil
                viewModel.reload()
                if !didComplete, let identity = onboardingConversationIdentity {
                    viewModel.offerDeferredOnboardingConversationIfNeeded(identity: identity)
                }
                if playbackKey != nil {
                    onOnboardingConversationPlaybackEnded(didComplete)
                }
                if let autoPlayedEventID {
                    onStoryEventAutoPlayEnded(
                        autoPlayedEventID,
                        didCompleteAutoPlayedEvent
                    )
                }
            }
        ) { launch in
            StoryPlaybackContainerView(
                launch: launch,
                allowsSkip: autoPlayedStoryEventID != "event_middle_001"
            ) {
                viewModel.closePlayer()
            }
        }
    }

    private var todayButton: some View {
        TodayConversationDockButton(
            title: viewModel.todayConversationTitle,
            isUnread: viewModel.todayConversationIsUnread,
            hasResumePosition: viewModel.todayConversationHasResumePosition,
            isAvailable: viewModel.todayConversationIsAvailable,
            action: {
                if let identity = onboardingConversationIdentity,
                   viewModel.openOnboardingConversation(identity: identity) {
                    onboardingPlaybackKeyInPlayer = identity.playbackKey
                } else {
                    viewModel.openToday()
                }
            }
        )
    }

    private var storyButton: some View {
        NavigationLink {
            storyCatalog
        } label: {
            InteractionDockItem(
                kind: .story,
                title: "ストーリー",
                showsUnreadDot: viewModel.hasUnreadStories
            )
        }
        .buttonStyle(InteractionDockButtonStyle())
        .accessibilityHint("メインストーリーとサブストーリーを開きます")
    }

    private var storyCatalog: some View {
        StoryCatalogView(
            mainChapters: viewModel.mainChapters,
            subChapters: viewModel.subChapters,
            onOpen: { _ = viewModel.openEvent(id: $0) }
        )
    }

    private var memoriesButton: some View {
        NavigationLink {
            MemoryGalleryView(memories: viewModel.memories)
        } label: {
            InteractionDockItem(kind: .memories, title: "思い出")
        }
        .buttonStyle(InteractionDockButtonStyle())
        .accessibilityHint("思い出のコレクションを開きます")
    }

    private func showNextHomeDialogue() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            viewModel.selectInteractionComment(touchArea: "character")
        }
    }

    private func openRequestedTodayConversationIfNeeded() {
        guard openTodayConversationRequest else { return }
        openTodayConversationRequest = false
        viewModel.configure(context: modelContext)
        guard let identity = onboardingConversationIdentity else {
            onOnboardingConversationUnavailable()
            return
        }
        let didOpen = viewModel.openOnboardingConversation(identity: identity)

        if didOpen {
            onboardingPlaybackKeyInPlayer = identity.playbackKey
        } else {
            onOnboardingConversationUnavailable()
        }
    }

    private func offerDeferredConversationIfNeeded() {
        guard let identity = onboardingConversationIdentity else { return }
        viewModel.offerDeferredOnboardingConversationIfNeeded(identity: identity)
    }

    private func openRequestedStoryEventIfNeeded() {
        guard let eventID = openStoryEventRequest else { return }
        viewModel.configure(context: modelContext)
        autoPlayedStoryEventID = eventID
        guard viewModel.openEvent(id: eventID) else {
            autoPlayedStoryEventID = nil
            openStoryEventRequest = nil
            onStoryEventAutoPlayEnded(eventID, false)
            return
        }
        openStoryEventRequest = nil
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
