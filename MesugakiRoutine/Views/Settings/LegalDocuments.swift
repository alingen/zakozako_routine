import Foundation

/// 設定から開く文書(利用規約・プライバシーポリシー・クレジット)。
///
/// TODO: いまはサンプル文面。公開前に正式な内容へ差し替え、`isSample` を false にする。
struct LegalDocument: Identifiable, Hashable {
    struct Section: Hashable {
        let heading: String
        let body: String
    }

    let id: String
    let title: String
    let updatedText: String
    let isSample: Bool
    let sections: [Section]
}

extension LegalDocument {
    static let terms = LegalDocument(
        id: "terms",
        title: "利用規約",
        updatedText: "最終更新日：2026年9月26日",
        isSample: true,
        sections: [
            Section(
                heading: "1. この規約について",
                body: "この規約は、「\(AppInfo.displayName)」（以下「本アプリ」）を利用するすべての方に適用されます。本アプリを利用した時点で、この規約に同意したものとみなします。"
            ),
            Section(
                heading: "2. 禁止事項",
                body: "本アプリの利用にあたり、法令に反する行為、他人になりすます行為、本アプリの運営を妨げる行為、本アプリの画像・文章・音声を無断で複製・配布する行為を禁止します。"
            ),
            Section(
                heading: "3. 本アプリの内容",
                body: "登場するキャラクター・団体・出来事はすべて架空のものです。キャラクターの発言は演出であり、利用者を傷つける意図はありません。本アプリは習慣づくりを手助けするものですが、効果を保証するものではありません。"
            ),
            Section(
                heading: "4. 変更・中断",
                body: "運営者は、事前の告知なく本アプリの内容を変更したり、提供を中断・終了したりすることがあります。"
            ),
            Section(
                heading: "5. 権利の帰属",
                body: "本アプリに含まれるイラスト・シナリオ・音声などの権利は、運営者または正当な権利者に帰属します。"
            ),
            Section(
                heading: "6. 免責",
                body: "本アプリの利用によって生じた損害について、運営者は故意または重大な過失がある場合を除き責任を負いません。"
            ),
            Section(
                heading: "7. 規約の変更",
                body: "この規約は必要に応じて変更することがあります。変更後の規約は、本アプリ内に掲載した時点で効力を持ちます。"
            ),
        ]
    )

    static let privacyPolicy = LegalDocument(
        id: "privacy",
        title: "プライバシーポリシー",
        updatedText: "最終更新日：2026年9月26日",
        isSample: true,
        sections: [
            Section(
                heading: "1. 扱う情報",
                body: "本アプリは、あなたが入力した名前、約束（続けたいこと）と「やらないこと」の内容と記録、ストーリーの進み具合、通知の設定を扱います。"
            ),
            Section(
                heading: "2. 保存場所",
                body: "これらの情報はすべてお使いの端末の中に保存され、運営者のサーバーなど外部へ送信することはありません。"
            ),
            Section(
                heading: "3. 名前の表示",
                body: "入力した名前は、「みんなのざこ速報」などアプリ内の表示に使われます。本名、メールアドレス、電話番号などの個人情報は入力しないでください。"
            ),
            Section(
                heading: "4. スクリーンタイムの利用",
                body: "「やらないこと」でアプリの利用時間の上限を設定した場合、Appleのスクリーンタイム機能を使って利用時間を判定します。どのアプリを選んだかや利用時間は端末内で処理され、運営者が受け取ることはありません。"
            ),
            Section(
                heading: "5. 通知",
                body: "約束の時間をお知らせするために、iOSの通知機能を使います。通知はいつでも設定から止められます。"
            ),
            Section(
                heading: "6. 第三者への提供",
                body: "法令に基づく場合を除き、情報を第三者に提供することはありません。"
            ),
            Section(
                heading: "7. 情報の削除",
                body: "本アプリを端末から削除すると、端末内に保存された情報もすべて削除されます。"
            ),
            Section(
                heading: "8. お問い合わせ",
                body: "このポリシーについてのお問い合わせは、設定の「お問い合わせ」からご連絡ください。"
            ),
        ]
    )

    static let credits = LegalDocument(
        id: "credits",
        title: "クレジット・ライセンス",
        updatedText: "最終更新日：2026年9月26日",
        isSample: true,
        sections: [
            Section(
                heading: "キャラクター・イラスト",
                body: "（制作者名を記載）"
            ),
            Section(
                heading: "シナリオ",
                body: "（制作者名を記載）"
            ),
            Section(
                heading: "BGM・効果音",
                body: "（提供元のサイト名・作者名を記載。クレジット表記が必要な素材はここに載せる）"
            ),
            Section(
                heading: "オープンソースソフトウェア",
                body: "現在、本アプリはサードパーティのオープンソースソフトウェアを使用していません。"
            ),
        ]
    )
}
