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
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button { onSelect(item) } label: { ZakoNewsRow(post: item) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct ZakoNewsRow: View {
    let post: ZakoNewsPost
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "megaphone.fill").font(.system(size: 17, weight: .semibold))
                .foregroundStyle(post.kind == "achievement" ? AppColor.secondary : AppColor.muted.opacity(0.5))
                .frame(width: 40, height: 40)
                .background((post.kind == "achievement" ? AppColor.secondary : AppColor.muted).opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.line).font(.subheadline).foregroundStyle(AppColor.text)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !post.comment.isEmpty {
                    Text("「\(post.comment)」").font(.caption).foregroundStyle(AppColor.muted).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(post.relativeTime).font(.caption2).foregroundStyle(AppColor.muted).lineLimit(1)
        }
        .padding(.vertical, 10).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("応援・通報などのメニューを開きます")
    }
}
