import SwiftUI

/// 「Hey Siri」でアプリを開くための設定方法を説明するヘルプ画面。
/// App Intents未実装のため、現状は「ショートカット」アプリでカスタムURL(zakozakoroutine://)を
/// 開くよう設定してもらう案内にとどめている。このURL経由で開いた時だけ、アプリ側が
/// 自動で数秒間の音声コマンド受付(「朝ルーティン」「夜ルーティン」など)を行う。
struct SiriShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("「Hey Siri、ざこざこルーティン開いて」のように話しかけてアプリを開き、そのまま「朝ルーティン」と言うだけでルーティンを始められるようにする設定です。iOS標準の「ショートカット」アプリを使います。")
                }

                Section("設定手順") {
                    step(number: 1, text: "「ショートカット」アプリを開く")
                    step(number: 2, text: "右上の「+」をタップして新規ショートカットを作成")
                    step(number: 3, text: "「アクションを追加」→「URLを開く」を選び、URL欄に「zakozakoroutine://open」と入力")
                    step(number: 4, text: "ショートカットの名前を「ざこざこルーティン開いて」など、話しかけたいフレーズに変更")
                    step(number: 5, text: "これで「Hey Siri、ざこざこルーティン開いて」と話しかけるとアプリが開き、数秒間だけ「朝ルーティン」「夜ルーティン」という声かけを受け付けます")
                }

                Section {
                    Text("この自動音声受付は、このURL経由でアプリが開かれた時だけ動きます。アイコンを手動でタップして開いた場合は今まで通り、「今日のルーティン」の「開始」をタップしてください。")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("補足")
                }
            }
            .navigationTitle("Hey Siriで開く設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
        }
    }
}

#Preview {
    SiriShortcutHelpView()
}
