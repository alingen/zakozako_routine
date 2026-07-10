import SwiftUI

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @State private var uiMode: AppUIMode = AppSettingsStore.uiMode

    var body: some View {
        List {
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
