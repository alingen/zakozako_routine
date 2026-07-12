import SwiftUI

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @State private var uiMode: AppUIMode = AppSettingsStore.uiMode
    @State private var userNickname: String = AppSettingsStore.userNickname
    @State private var completionPhrase: String = AppSettingsStore.completionPhrase

    var body: some View {
        List {
            Section {
                TextField("例: おにいさん、おねえさん", text: $userNickname)
                    .onChange(of: userNickname) {
                        AppSettingsStore.userNickname = userNickname
                    }
            } header: {
                Text("呼び名")
            } footer: {
                Text("キャラクターがあなたを呼ぶ時の呼び名です。空欄なら特に呼びかけません。")
            }

            Section {
                Picker(selection: $uiMode) {
                    ForEach(AppUIMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .onChange(of: uiMode) {
                    AppSettingsStore.uiMode = uiMode
                }
            } header: {
                Text("モード")
            } footer: {
                Text("\(uiMode.description)\n見た目の切り替えは準備中で、現在はまだ反映されません。")
            }

            Section {
                TextField("例: できた", text: $completionPhrase)
                    .onChange(of: completionPhrase) {
                        AppSettingsStore.completionPhrase = completionPhrase
                    }
            } header: {
                Text("音声コマンド")
            } footer: {
                Text("音声会話中(またはテキスト入力)でこの発言をすると、現在のステップを完了として次に進みます。")
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
