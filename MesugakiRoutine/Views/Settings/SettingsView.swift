import SwiftUI

/// 設定タブのトップ画面。設定項目の一覧から各設定画面へ遷移する。
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("一般") {
                GeneralSettingsView()
            }
            NavigationLink("通知") {
                NotificationSettingsView()
            }
        }
        .navigationTitle("設定")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
