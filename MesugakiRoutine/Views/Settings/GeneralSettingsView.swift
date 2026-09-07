import SwiftUI

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @State private var userName: String = AppSettingsStore.userName
    @State private var userHonorific: UserHonorific = AppSettingsStore.userHonorific

    private var previewName: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? userHonorific.displayName : name + userHonorific.displayName
    }

    var body: some View {
        List {
            Section {
                TextField("例: だいすけ", text: $userName)
                    .onChange(of: userName) { AppSettingsStore.userName = userName }
                Picker("よびかた", selection: $userHonorific) {
                    ForEach(UserHonorific.allCases) { honorific in
                        Text(honorific.displayName).tag(honorific)
                    }
                }
                .onChange(of: userHonorific) { AppSettingsStore.userHonorific = userHonorific }
            } header: {
                Text("あなたのこと")
            } footer: {
                Text("みんなのざこ速報の表示に使います(例: 「\(previewName)」)。")
            }

        }
        .navigationTitle("一般")
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
