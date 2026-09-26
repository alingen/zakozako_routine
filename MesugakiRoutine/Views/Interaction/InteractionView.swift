import SwiftData
import SwiftUI

/// キャラクターコンテンツの入口。習慣操作はHomeへ残し、会話・物語・思い出だけを扱う。
struct InteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = InteractionViewModel()
    /// タップしたときに莉央が跳ねる量(上がマイナス)。
    @State private var rioHopOffset: CGFloat = 0
    /// タップした位置に出す小さなきらめき。
    @State private var tapSparkles: [InteractionTapSparkle.Burst] = []
    @State private var onboardingPlaybackKeyInPlayer: String?
    @State private var autoPlayedStoryEventID: String?
    @State private var isVisible = false

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
        viewModel.interactionComment?.displayText
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = proxy.size.height + proxy.safeAreaInsets.bottom
            let backgroundHeight = visualHeight + proxy.safeAreaInsets.top
            let artworkDrop = min(48, proxy.size.height * 0.055)
            // 立ち絵は幅から決めつつ、表示領域の高さでも上限を設ける。SEのように幅が同じで
            // 背の低い端末では少し小さく描き、顔の位置も高さの割合で決めて吹き出しと被らせない。
            // (iPhone 13 mini では従来と同じ大きさ・位置になる値)
            let artworkWidth = min(proxy.size.width * 1.8, proxy.size.height)
            let artworkTop = proxy.size.height * 0.2435
            // 吹き出しは莉央の顔のすぐ下(あごの少し下、スカーフの結び目の高さ)から下へ伸ばす。
            // あごは立ち絵の上端から幅の約22%の位置にある。
            let bubbleTop = artworkTop + artworkWidth * 0.32

            ZStack(alignment: .top) {
                AppColor.background
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    Image("bg_rio_room")
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: backgroundHeight,
                            alignment: .top
                        )
                        .clipped()
                        .offset(y: -proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .bottom)

                    Image("rio_interaction_home")
                        .resizable()
                        .scaledToFit()
                        .frame(width: artworkWidth)
                        .offset(y: artworkTop + rioHopOffset)
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

                // 時刻が読めるよう上端だけ薄く重ねる。部屋の色と窓の光は消さない。
                LinearGradient(
                    colors: [
                        AppColor.background.opacity(0.16),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .center
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
                // ボタンの動作はそのままに、きらめきを出す位置だけ受け取る。
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(Self.coordinateSpace))
                        .onEnded { addTapSparkle(at: $0.location) }
                )
                .accessibilityLabel("莉央")
                .accessibilityHint("タップすると莉央が話します")

                ForEach(tapSparkles) { burst in
                    InteractionTapSparkle()
                        .position(burst.location)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

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

                    Spacer(minLength: 0)
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(alignment: .leading, spacing: 0) {
                    // 上端は顔を基準に固定し、下のバーから積まない(行数が変わっても書き出しの位置が動かない)。
                    // 大きな文字で入りきらないときだけ、優先度を上げたこの余白が縮んで上に持ち上がる。
                    Color.clear
                        .frame(maxHeight: bubbleTop)
                        .layoutPriority(1)

                    if let homeDialogue {
                        InteractionCharacterSpeechBubble(text: homeDialogue, speakerName: "莉央")
                            .frame(width: min(300, proxy.size.width - 32))
                            .padding(.leading, 16)
                            .id(viewModel.interactionComment?.id)
                            .transition(
                                .scale(scale: 0.94, anchor: .top)
                                    .combined(with: .opacity)
                            )
                            .allowsHitTesting(false)
                    }

                    Spacer(minLength: 16)

                    // 入口は1本のバーに3つだけ並べ、莉央の見える範囲を広く取る。
                    InteractionDock {
                        todayButton
                        storyButton
                        memoriesButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                // 立ち絵の上に重ねる操作群なので、極端な文字サイズでは莉央を覆い尽くさないよう上限を設ける。
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .frame(width: proxy.size.width, height: proxy.size.height)

                if let loadError = viewModel.loadError {
                    VStack {
                        Label {
                            Text(loadError)
                                .foregroundStyle(AppColor.text)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColor.warning)
                        }
                            .font(.caption)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
                            .padding(16)
                        Spacer()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: Self.coordinateSpace)
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
            isVisible = true
            viewModel.configure(context: modelContext)
            viewModel.recordInteractionScreenOpen(context: modelContext)
            offerDeferredConversationIfNeeded()
        }
        .onDisappear { isVisible = false }
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
            if phase == .active && isVisible {
                viewModel.reload()
                if viewModel.activeLaunch == nil {
                    viewModel.recordInteractionScreenOpen(context: modelContext)
                }
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

    private static let coordinateSpace = "interactionScreen"

    private func showNextHomeDialogue() {
        hopRio()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            viewModel.selectInteractionComment(touchArea: "character")
        }
    }

    /// タップに応えて、莉央を6ptだけ跳ねさせる。視差効果を減らす設定では動かさない。
    private func hopRio() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.11)) {
            rioHopOffset = -6
        } completion: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                rioHopOffset = 0
            }
        }
    }

    private func addTapSparkle(at location: CGPoint) {
        let burst = InteractionTapSparkle.Burst(location: location)
        tapSparkles.append(burst)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            tapSparkles.removeAll { $0.id == burst.id }
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
            UserActionEvent.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ],
        inMemory: true
    )
}
