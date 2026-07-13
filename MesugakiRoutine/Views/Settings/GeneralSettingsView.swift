import SwiftUI
import SwiftData

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var uiMode: AppUIMode = AppSettingsStore.uiMode
    @State private var userNickname: String = AppSettingsStore.userNickname
    @State private var completionPhrase: String = AppSettingsStore.completionPhrase
    @State private var trustPoints: Int = 0

    private var trustRepository: TrustRepository { TrustRepository(context: modelContext) }

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

            Section {
                Text("現在: ステージ\(TrustStage.stage(for: trustPoints))(\(trustPoints)pt)")
                    .font(.subheadline)
                Button("低ステージにする") {
                    setTrustPoints(0)
                }
                Button("中ステージにする") {
                    setTrustPoints(TrustStage.pointsPerStage * 2)
                }
                Button("高ステージにする") {
                    setTrustPoints(TrustStage.pointsPerStage * 5)
                }
            } header: {
                Text("信頼度(デバッグ用)")
            } footer: {
                Text("信頼度ステージによる応答の変化を確認するためのテスト用ボタンです。")
            }
        }
        .navigationTitle("一般")
        .task {
            trustPoints = trustRepository.points
        }
    }

    private func setTrustPoints(_ points: Int) {
        trustRepository.setPoints(points)
        trustPoints = points
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
