import SwiftUI

/// メインキャラクターのプロフィール(自己紹介)画面。
/// 現状はキャラクターが1体のみのため、プリセットに紐づけず固定の内容として持たせている。
struct CharacterProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        Image("CharacterIcon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    profileRow(label: "名前", value: "黒川莉央")
                    profileRow(label: "出身", value: "東京都世田谷区生まれ")
                    profileRow(label: "家族構成", value: "ひとりっこ。両親共働き")
                    profileRow(label: "好きなこと", value: "ダンス。韓国系のファッションが好き。")
                    profileRow(
                        label: "学校では",
                        value: "先生には一応敬語を使う。宿題はめんどくさがりながらもちゃんと提出するタイプ。"
                    )
                    profileRow(label: "性格", value: "さびしがりやで、人に構ってもらうために煽りがち。")
                }
            }
            .navigationTitle("小悪魔コーチ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func profileRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    CharacterProfileView()
}
