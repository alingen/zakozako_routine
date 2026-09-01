import SwiftUI

/// 「みんなのざこ速報」の1件。
/// ※ まだバックエンド・投稿基盤は無い。ネットワーク/アカウント/投稿は別Step。
/// このStepでは仮データを流す値型に留める。将来は本物のフィード源に差し替える。
struct ZakoBulletinItem: Identifiable {
    let id: UUID
    let handle: String
    let text: String
    let relativeTime: String
}

/// フィードの供給元。将来ネットワーク実装(`RemoteZakoBulletinProvider` 等)に差し替えられるよう protocol にしておく。
protocol ZakoBulletinProviding {
    /// Home では 3〜5件程度のみ表示する(無限スクロールにはしない)。
    func latest(limit: Int) -> [ZakoBulletinItem]
}

/// 仮データ。
struct SampleZakoBulletinProvider: ZakoBulletinProviding {
    func latest(limit: Int) -> [ZakoBulletinItem] {
        let all: [ZakoBulletinItem] = [
            .init(id: UUID(), handle: "ざこ_087", text: "15分勉強、7日継続中！さすがわたし", relativeTime: "3分前"),
            .init(id: UUID(), handle: "ざこ_042", text: "莉央に怒られてやっと風呂入った…", relativeTime: "1時間前"),
            .init(id: UUID(), handle: "ざこ_213", text: "今日の約束、あぶなかったけど守れた", relativeTime: "2時間前"),
            .init(id: UUID(), handle: "ざこ_001", text: "3日連続で朝サボった。もうだめかも", relativeTime: "4時間前"),
        ]
        return Array(all.prefix(limit))
    }
}

/// 「みんなのざこ速報」セクションの中身。差し替え可能なようにここに閉じ込める。
struct ZakoBulletinFeedView: View {
    var provider: ZakoBulletinProviding = SampleZakoBulletinProvider()
    var limit: Int = 4

    private var items: [ZakoBulletinItem] { provider.latest(limit: limit) }

    var body: some View {
        if items.isEmpty {
            Text("まだ速報はありません")
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)
        } else {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("@\(item.handle)")
                            .font(.caption.bold())
                            .foregroundStyle(AppColor.secondary)
                        Spacer()
                        Text(item.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                    }
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text)
                }
                .padding(.vertical, 2)
            }
            Text("※ サンプル表示です（フィード連携は今後）")
                .font(.caption2)
                .foregroundStyle(AppColor.muted)
        }
    }
}
