import SwiftUI

struct DestructiveConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: () -> Void
}

/// アプリのルート画面。ホーム/記録/交流/設定をボトムタブで切り替える。
struct RootTabView: View {
    @State private var destructiveConfirmation: DestructiveConfirmationRequest?

    var body: some View {
        ZStack {
            TabView {
                NavigationStack {
                    HomeView(destructiveConfirmation: $destructiveConfirmation)
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

            if let destructiveConfirmation {
                destructiveConfirmationOverlay(destructiveConfirmation)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: destructiveConfirmation?.id)
        // 配色はライト前提の単一値パレットのため、ダーク時に破綻しないよう固定する。
        .preferredColorScheme(.light)
    }

    private func destructiveConfirmationOverlay(_ request: DestructiveConfirmationRequest) -> some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    destructiveConfirmation = nil
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(request.title)
                        .font(.headline)
                        .foregroundStyle(AppColor.text)

                    Text(request.message)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Button("いいえ") {
                        destructiveConfirmation = nil
                    }
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.background, in: Capsule())

                    Button("はい", role: .destructive) {
                        destructiveConfirmation = nil
                        request.onConfirm()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.error, in: Capsule())
                }
            }
            .padding(24)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 32)
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
