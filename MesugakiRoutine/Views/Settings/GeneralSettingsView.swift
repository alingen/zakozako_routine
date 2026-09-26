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
                // ざこ速報に公開する名前にもなるので、オンボーディングと同じく入力の時点で10文字までにする。
                TextField("例: だいすけ", text: $userName)
                    .onChange(of: userName) {
                        if userName.count > ZakoNewsConfiguration.nameLimit {
                            userName = String(userName.prefix(ZakoNewsConfiguration.nameLimit))
                        }
                        AppSettingsStore.userName = userName
                    }
            } header: {
                Text("あなたのこと")
            } footer: {
                Text("\(ZakoNewsConfiguration.nameLimit)文字まで。莉央からは「おにいさん」と呼ばれます。みんなのざこ速報では「\(previewName)」と表示します。")
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
