import SwiftUI

enum ZakoBulletinKind: Equatable {
    case achievement
    case failure
}

/// 「みんなのざこ速報」の1件。1ユーザーぶんの速報を1行に収める。
/// 例: 「だいすけおにいさんが 散歩する を達成しました！」
struct ZakoBulletinItem: Identifiable {
    let id: UUID
    /// 1行で表示する速報本文。
    let line: String
    /// 「3分前」などの相対時刻。
    let relativeTime: String
    /// 達成／未達成に応じたメガホンの配色に使う。
    let kind: ZakoBulletinKind
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
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 52)
                    }

                    bulletinRow(item)
                }
            }
        }
    }

    private func bulletinRow(_ item: ZakoBulletinItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconColor(for: item.kind))
                .frame(width: 40, height: 40)
                .background(iconBackgroundColor(for: item.kind), in: Circle())
                .accessibilityHidden(true)

            Text(item.line)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.relativeTime)
                .font(.caption2)
                .foregroundStyle(AppColor.muted)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func iconColor(for kind: ZakoBulletinKind) -> Color {
        switch kind {
        case .achievement:
            return AppColor.primary
        case .failure:
            return AppColor.muted.opacity(0.5)
        }
    }

    private func iconBackgroundColor(for kind: ZakoBulletinKind) -> Color {
        switch kind {
        case .achievement:
            return AppColor.primarySoft.opacity(0.72)
        case .failure:
            return AppColor.muted.opacity(0.12)
        }
    }
}

#Preview {
    List {
        Section {
            ZakoBulletinFeedView(
                items: [
                    ZakoBulletinItem(
                        id: UUID(),
                        line: "ひろみちおにいさんが 10分勉強する を達成しました！",
                        relativeTime: "7時間前",
                        kind: .achievement
                    ),
                    ZakoBulletinItem(
                        id: UUID(),
                        line: "ひろみちおにいさんが スマホを見ない に負けました…",
                        relativeTime: "14時間前",
                        kind: .failure
                    ),
                ]
            )
        } header: {
            Label("みんなのざこ速報", systemImage: "ellipsis.bubble")
                .font(.headline)
                .foregroundStyle(AppColor.text)
                .textCase(nil)
        }
        .appCardRow()
    }
    .appScreenBackground()
}
