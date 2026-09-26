import SwiftUI

struct ZakoNewsSharingSection: View {
    @Binding var isOn: Bool
    let title: String
    @AppStorage("zako_news_sharing_consent_v1") private var consented = false
    @State private var showsConsent = false

    var body: some View {
        Section {
            Toggle("みんなと共有する", isOn: Binding(
                get: { isOn },
                set: { value in
                    if value && !consented { showsConsent = true } else { isOn = value }
                }
            ))
            .tint(AppColor.primary)
        } footer: {
            if isOn && !ZakoNewsText.canShare(title: title) {
                Text(ZakoNewsText.validationMessage).foregroundStyle(AppColor.error)
            } else {
                Text("ONにした後の達成・手動の敗北報告だけを共有します。過去の記録や自動判定は投稿しません。")
            }
        }
        .alert("みんなと共有する", isPresented: $showsConsent) {
            Button("キャンセル", role: .cancel) {}
            Button("共有をONにする") { consented = true; isOn = true }
        } message: {
            Text("達成・負けた結果などが、匿名で『ざこ速報』に表示されることがあります。\n\n公開例：たけしおにいさんが『朝ラン』を達成しました\n\n名前・項目名・ひとことは公開されます。個人情報は入力しないでください。")
        }
    }
}
