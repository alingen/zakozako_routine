import SwiftUI

/// 「みんなのざこ速報」の1件。1ユーザーぶんの速報を1行に収める。
/// 例: 「だいすけおにいさんが 散歩する を達成しました！」
struct ZakoBulletinItem: Identifiable {
    let id: UUID
    /// 1行で表示する速報本文。
    let line: String
    /// 「3分前」などの相対時刻。
    let relativeTime: String
}

/// 「みんなのざこ速報」セクションの中身。
/// ※ バックエンド未接続のため、いまは自分の記録だけを速報形式で流している。
///   将来は他ユーザーぶんも混ざる想定なのでセクション名は「みんなの」のまま。
struct ZakoBulletinFeedView: View {
    let items: [ZakoBulletinItem]

    var body: some View {
        if items.isEmpty {
            Text("まだ速報はありません")
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)
        } else {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.line)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(item.relativeTime)
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                        .layoutPriority(1)
                }
                .padding(.vertical, 2)
            }
            Text("※ いまは自分の記録だけ表示しています（フィード連携は今後）")
                .font(.caption2)
                .foregroundStyle(AppColor.muted)
        }
    }
}
