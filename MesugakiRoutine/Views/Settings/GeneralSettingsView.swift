import SwiftUI

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @State private var uiMode: AppUIMode = AppSettingsStore.uiMode
    @State private var userNickname: String = AppSettingsStore.userNickname

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
                Text("キャラクターがあなたを呼ぶ時の呼び名です。空欄なら特に呼びかけません。ルーティン開始時だけは頭に「ざこの」が付きます(例: ざこのおにいさん)。")
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
        }
        .navigationTitle("一般")
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
