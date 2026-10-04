import SwiftUI

struct ZakoBulletinFeedView: View {
    let items: [ZakoNewsPost]
    let onSelect: (ZakoNewsPost) -> Void
    var body: some View {
        if items.isEmpty {
            Text("まだ速報はありません").font(.subheadline).foregroundStyle(AppColor.muted)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    // ホームでは上の約束カードのアイコン(52pt)と中心をそろえる。区切り線は本文の先頭(52+12)から。
                    if index > 0 { Divider().padding(.leading, 64) }
                    Button { onSelect(item) } label: { ZakoNewsRow(post: item, iconColumnWidth: 52) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct ZakoNewsRow: View {
    let post: ZakoNewsPost
    var iconColumnWidth: CGFloat = 40
    /// 自分の投稿の目印。全部が自分の投稿になる「自分の速報」一覧では出さない。
    var showsMineBadge = true
    var body: some View {
        HStack(spacing: 12) {
            ZakoNewsKindIcon(post: post, showsMineBadge: showsMineBadge)
                .frame(width: iconColumnWidth)
            VStack(alignment: .leading, spacing: 2) {
                // 文面はそのまま残し、定型の「○○おにいさんが」の後で改行して変な位置で折り返さないようにする。
                // 名前は10文字まで(ZakoNewsConfiguration.nameLimit)で、幅375ptの端末でも1行に収まる。
                // 縮小(minimumScaleFactor)は行ごとに大きさがばらつくので使わず、大きな文字サイズでは折り返させる。
                Text(post.subjectText).font(.subheadline).foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(post.resultText).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.text)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !post.comment.isEmpty {
                    Text("「\(post.comment)」").font(.caption).foregroundStyle(AppColor.muted).lineLimit(2)
                } else if post.isMine {
                    // 自分の投稿でひとことが空のときだけ、ひとことが入る場所に控えめに案内する(赤い点などは付けない)。
                    Label("ひとことを添える", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            // 一覧は幅が狭いので時刻は出さない(詳細で見られる)。
        }
        .padding(.vertical, 10).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(post.isMine ? "ひとことを添えられます" : "応援・通報などのメニューを開きます")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if post.isMine { parts.append(post.comment.isEmpty ? "自分の速報。ひとこと未入力" : "自分の速報") }
        parts.append(post.line)
        if !post.comment.isEmpty { parts.append("ひとこと、\(post.comment)") }
        return parts.joined(separator: "、")
    }
}

/// 速報の種類を表すアイコン。達成はホームの完了と同じ Purple、負けは失敗を表す Error。
struct ZakoNewsKindIcon: View {
    let post: ZakoNewsPost
    var showsMineBadge = true

    private var isAchievement: Bool { post.kind == "achievement" }
    private var tint: Color { isAchievement ? AppColor.secondary : AppColor.error }

    var body: some View {
        Image(systemName: isAchievement ? "checkmark" : "xmark")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.12), in: Circle())
            // 自分の投稿は右下に小さな人のバッジ(Yahoo天気と同じ考え方)。達成の Purple とぶつからないよう muted にする。
            .overlay(alignment: .bottomTrailing) {
                if post.isMine && showsMineBadge {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(AppColor.muted, in: Circle())
                        .overlay(Circle().stroke(AppColor.surface, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}
