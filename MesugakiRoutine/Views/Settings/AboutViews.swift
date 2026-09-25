import SwiftUI
import UIKit

/// 利用規約・プライバシーポリシーなどの文書を読む画面。
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.updatedText)
                        .font(.footnote)
                        .foregroundStyle(AppColor.text)

                    if document.isSample {
                        Text("この文面はサンプルです。公開前に正式な内容へ差し替えます。")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.error)
                    }
                }

                ForEach(document.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading)
                            .font(.headline)
                            .foregroundStyle(AppColor.text)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(AppColor.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .textSelection(.enabled)
        }
        .background(AppColor.surface)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// お問い合わせ画面。メールアプリで下書きを開くか、アドレスをコピーして使ってもらう。
struct ContactView: View {
    @Environment(\.openURL) private var openURL
    @State private var isShowingMailError = false
    @State private var didCopy = false

    var body: some View {
        List {
            Section {
                Text("ご意見・ご要望や不具合のご報告は、下記のメールアドレスまでお送りください。返信までにお時間をいただくことがあります。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
            }

            Section {
                LabeledContent("メールアドレス") {
                    Text(AppInfo.supportEmail)
                        .foregroundStyle(AppColor.text)
                        .textSelection(.enabled)
                }

                Button {
                    guard let url = AppInfo.supportMailURL() else {
                        isShowingMailError = true
                        return
                    }
                    openURL(url) { accepted in
                        if !accepted { isShowingMailError = true }
                    }
                } label: {
                    Label("メールアプリで作成", systemImage: "envelope")
                }

                Button {
                    UIPasteboard.general.string = AppInfo.supportEmail
                    didCopy = true
                } label: {
                    Label(didCopy ? "コピーしました" : "アドレスをコピー", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
            } footer: {
                Text("※ 現在のお問い合わせ先は仮のものです。")
            }
        }
        .navigationTitle("お問い合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .alert("メールアプリを開けませんでした", isPresented: $isShowingMailError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("お手数ですが、アドレスをコピーしてお使いのメールアプリからお送りください。")
        }
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(document: .privacyPolicy)
    }
}
