import SwiftUI

/// アプリのルート画面。ホーム/記録/設定をボトムタブで切り替える。
struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
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
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
        }
        .tint(AppColor.primary)
        // 配色はライト前提の単一値パレットのため、ダーク時に破綻しないよう固定する。
        .preferredColorScheme(.light)
    }
}

#Preview {
    RootTabView()
        .environment(SiriLaunchCoordinator())
        .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self, BlockedBehavior.self], inMemory: true)
}
