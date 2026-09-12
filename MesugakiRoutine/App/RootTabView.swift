import SwiftUI

enum AppDialogActionStyle: Equatable {
    case standard
    case destructive
}

enum AppDialogActionResult {
    case dismiss
    case replace(AppDialogRequest)
    case showTaunt(BlockedBehaviorTauntRequest)
}

struct AppDialogAction: Identifiable {
    let id = UUID()
    let title: String
    let style: AppDialogActionStyle
    let action: () -> AppDialogActionResult

    init(
        _ title: String,
        style: AppDialogActionStyle = .standard,
        action: @escaping () -> AppDialogActionResult
    ) {
        self.title = title
        self.style = style
        self.action = action
    }
}

struct AppDialogRequest: Identifiable {
    let id = UUID()
    let title: String?
    let message: String?
    let actions: [AppDialogAction]
}

struct BlockedBehaviorTauntRequest: Identifiable {
    let id = UUID()
    let text: String
}

/// アプリのルート画面。ホーム/記録/交流/設定をボトムタブで切り替える。
struct RootTabView: View {
    @State private var appDialog: AppDialogRequest?
    @State private var blockedBehaviorTaunt: BlockedBehaviorTauntRequest?

    private var isPresentingOverlay: Bool {
        appDialog != nil || blockedBehaviorTaunt != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationStack {
                    HomeView(appDialog: $appDialog)
                }
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }

                NavigationStack {
                    RoutineLogView()
                }
                .tabItem {
                    Label("記録", systemImage: "list.bullet.clipboard")
                }

                NavigationStack {
                    InteractionView()
                }
                .tabItem {
                    Label("交流", systemImage: "sparkles")
                }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
            }
            .tint(AppColor.primary)
            .allowsHitTesting(!isPresentingOverlay)
            .accessibilityHidden(isPresentingOverlay)

            if isPresentingOverlay {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissPresentedOverlay)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if let appDialog {
                appDialogCard(appDialog)
                    .id(appDialog.id)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                    .zIndex(2)
            }

            if let blockedBehaviorTaunt {
                Button(action: dismissBlockedBehaviorTaunt) {
                    blockedBehaviorTauntOverlay(blockedBehaviorTaunt)
                }
                .buttonStyle(.plain)
                .id(blockedBehaviorTaunt.id)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 32)
                            .combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresentingOverlay)
        .animation(.easeInOut(duration: 0.18), value: appDialog?.id)
        .animation(.easeOut(duration: 0.28), value: blockedBehaviorTaunt?.id)
        // 配色はライト前提の単一値パレットのため、ダーク時に破綻しないよう固定する。
        .preferredColorScheme(.light)
    }

    private func appDialogCard(_ request: AppDialogRequest) -> some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    if let title = request.title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppColor.text)
                    }

                    if let message = request.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.muted)
                            .multilineTextAlignment(.center)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        dialogButtons(for: request)
                    }

                    VStack(spacing: 12) {
                        dialogButtons(for: request)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 32)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                appDialog = nil
            }
        }
    }

    @ViewBuilder
    private func dialogButtons(for request: AppDialogRequest) -> some View {
        ForEach(request.actions) { action in
            Button(role: action.style == .destructive ? .destructive : nil) {
                handle(action.action())
            } label: {
                Text(action.title)
                    .font(.headline)
                    .foregroundStyle(action.style == .destructive ? Color.white : AppColor.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        action.style == .destructive ? AppColor.error : AppColor.background,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func handle(_ result: AppDialogActionResult) {
        switch result {
        case .dismiss:
            appDialog = nil
        case let .replace(request):
            appDialog = request
        case let .showTaunt(request):
            appDialog = nil
            blockedBehaviorTaunt = request
        }
    }

    private func blockedBehaviorTauntOverlay(_ request: BlockedBehaviorTauntRequest) -> some View {
        GeometryReader { proxy in
            let artworkWidth = min(
                430,
                min(proxy.size.width * 1.04, proxy.size.height * 0.50)
            )
            let bubbleWidth = min(312, proxy.size.width - 40)
            let bubbleBottomPadding = max(
                proxy.safeAreaInsets.bottom + 96,
                proxy.size.height * 0.26
            )

            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())

                Image("rio_blocked_behavior_taunt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: artworkWidth)
                    .offset(x: max(12, proxy.size.width * 0.04))
                    .padding(.bottom, bubbleBottomPadding + 42)
                    .accessibilityHidden(true)

                InteractionCharacterSpeechBubble(text: request.text)
                    .frame(width: bubbleWidth)
                    .padding(.bottom, bubbleBottomPadding)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(request.text)")
        .accessibilityHint("タップして閉じる")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.escape, dismissBlockedBehaviorTaunt)
    }

    private func dismissBlockedBehaviorTaunt() {
        blockedBehaviorTaunt = nil
    }

    private func dismissPresentedOverlay() {
        if blockedBehaviorTaunt != nil {
            dismissBlockedBehaviorTaunt()
        } else {
            appDialog = nil
        }
    }
}

#Preview {
    RootTabView()
        .environment(SiriLaunchCoordinator())
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
