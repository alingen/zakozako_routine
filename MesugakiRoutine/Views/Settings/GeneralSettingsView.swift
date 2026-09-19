import SwiftUI

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @State private var userName: String = AppSettingsStore.userName

    private var previewName: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "おにいさん" : name + "おにいさん"
    }

    var body: some View {
        List {
            Section {
                TextField("例: だいすけ", text: $userName)
                    .onChange(of: userName) { AppSettingsStore.userName = userName }
            } header: {
                Text("あなたのこと")
            } footer: {
                Text("莉央からは「おにいさん」と呼ばれます。みんなのざこ速報では「\(previewName)」と表示します。")
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
