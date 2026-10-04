import SwiftUI

/// ストーリー一覧。章(とプロローグ)をカードで並べ、章を開くと各話が並ぶ。
struct StoryCatalogView: View {
    let mainChapters: [StoryChapterPresentation]
    let subChapters: [StoryChapterPresentation]
    let onOpen: (String) -> Void

    @State private var category: StoryCategory = .main

    private var groups: [StoryCatalogGroup] {
        StoryCatalogGroup.groups(from: category == .main ? mainChapters : subChapters)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("ストーリー区分", selection: $category) {
                    Text("メイン").tag(StoryCategory.main)
                    Text("サブ").tag(StoryCategory.sub)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)

                if groups.isEmpty {
                    ContentUnavailableView(
                        "まだストーリーがありません",
                        systemImage: "book.closed",
                        description: Text("追加されたストーリーはここに表示されます")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(groups) { group in
                        entry(for: group)
                    }
                }
            }
            .padding()
        }
        .background(AppColor.background)
        .navigationTitle("ストーリー")
        // 他の階層の画面(章・達成状況など)と同じく小さな題名にそろえる。
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 1話だけの入口(プロローグ)はすぐ再生し、章は各話の一覧を開く。
    @ViewBuilder
    private func entry(for group: StoryCatalogGroup) -> some View {
        if group.stories.count == 1, let story = group.stories.first {
            Button {
                guard story.isUnlocked else { return }
                onOpen(story.id)
            } label: {
                StoryChapterCard(group: group)
            }
            .buttonStyle(.plain)
            // .disabled だと全体が薄くなり、解放条件まで読めなくなる。押せなくするだけにする。
            .accessibilityRemoveTraits(story.isUnlocked ? [] : .isButton)
            .accessibilityHint(story.isUnlocked ? "ストーリーを開きます" : "解放条件を達成すると開けます")
        } else if group.isUnlocked {
            NavigationLink {
                StoryChapterView(group: group, onOpen: onOpen)
            } label: {
                StoryChapterCard(group: group)
            }
            .buttonStyle(.plain)
            .accessibilityHint("各話の一覧を開きます")
        } else {
            // 未解放の章はリンクにしない(.disabled だと解放条件まで薄くなるため)。
            StoryChapterCard(group: group)
                .accessibilityHint("解放条件を達成すると開けます")
        }
    }
}

/// 章の入口のカード。左に背景画像、右に章名と読んだ話数。
private struct StoryChapterCard: View {
    let group: StoryCatalogGroup

    var body: some View {
        HStack(spacing: 0) {
            StoryAssetView(
                assetID: group.thumbnailAssetId,
                purpose: .background,
                contentMode: .fill
            )
            .frame(width: 112, height: 88)
            .clipped()
            .saturation(group.isUnlocked ? 1 : 0)
            .opacity(group.isUnlocked ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(.headline)
                        .foregroundStyle(group.isUnlocked ? AppColor.text : AppColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if group.hasNew && group.isUnlocked {
                        Text("NEW")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppColor.primary, in: Capsule())
                    }
                }

                if group.isUnlocked {
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                        .monospacedDigit()
                } else {
                    // 未解放のときにいちばん読ませたいのは解放条件なので、文字は本文色にする。
                    Label {
                        Text(group.unlockHint.map { "\($0)で解放" } ?? "未解放")
                            .foregroundStyle(AppColor.text)
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(AppColor.muted)
                    }
                    .font(.caption)
                    .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            if group.isUnlocked {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
                    .padding(.trailing, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var progressText: String {
        if group.stories.count == 1 {
            return group.readCount == 1 ? "読了" : "未読"
        }
        return "\(group.readCount) / \(group.stories.count)話"
    }

    private var accessibilityLabel: String {
        var parts = [group.title]
        if group.isUnlocked {
            parts.append(progressText)
            if group.hasNew { parts.append("新しい話あり") }
        } else {
            parts.append(group.unlockHint.map { "\($0)で解放" } ?? "未解放")
        }
        return parts.joined(separator: "、")
    }
}

/// 章の中の各話の一覧。ストーリー一覧と同じく、白いカード(角丸20・枠1pt)に各話を区切り線で並べる。
struct StoryChapterView: View {
    let group: StoryCatalogGroup
    let onOpen: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(group.stories.enumerated()), id: \.element.id) { index, story in
                    if index > 0 {
                        // 区切り線の左端は本文の先頭(サムネイルの右)にそろえる。
                        Rectangle()
                            .fill(AppColor.border)
                            .frame(height: 1)
                            .padding(.leading, StoryListRow.textLeading)
                    }
                    StoryListRow(item: story) {
                        onOpen(story.id)
                    }
                }
            }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 1)
            }
            .padding()
        }
        .background(AppColor.background)
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StoryListRow: View {
    let item: StoryListItemPresentation
    let action: () -> Void

    /// SE でも6話以上入るよう、行の高さを約84pt(サムネイル60＋上下12)に抑える。
    private static let thumbnailSize: CGFloat = 60
    private static let horizontalPadding: CGFloat = 16
    private static let spacing: CGFloat = 12
    /// 本文の先頭の位置。区切り線の左端に使う。
    static let textLeading = horizontalPadding + thumbnailSize + spacing

    var body: some View {
        Button {
            guard item.isUnlocked else { return }
            action()
        } label: {
            HStack(alignment: .top, spacing: Self.spacing) {
                StoryAssetView(
                    assetID: item.backgroundAssetId,
                    purpose: .background,
                    contentMode: .fill,
                    cornerRadius: 0
                )
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .saturation(item.isUnlocked ? 1 : 0)
                .opacity(item.isUnlocked ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        if let episodeLabel = item.episodeLabel {
                            Text(episodeLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.muted)
                        }
                        if item.isNew {
                            Text("NEW")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppColor.primary, in: Capsule())
                        }
                    }

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(item.isUnlocked ? AppColor.text : AppColor.muted)
                        .multilineTextAlignment(.leading)

                    if !item.isUnlocked {
                        conditionSummary
                    }
                }

                Spacer(minLength: 6)
                // 行全体がタップ対象なので、シェブロンは目立たせず muted にする。
                Image(systemName: item.isUnlocked ? "chevron.right" : "lock.fill")
                    .foregroundStyle(AppColor.muted)
                    .padding(.top, 20)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // .disabled だと全体が薄くなり、解放条件まで読めなくなる。押せなくするだけにする。
        .accessibilityRemoveTraits(item.isUnlocked ? [] : .isButton)
        .accessibilityHint(item.isUnlocked ? "ストーリーを開きます" : "解放条件を達成すると開けます")
    }

    @ViewBuilder
    private var conditionSummary: some View {
        if item.conditions.isEmpty {
            Text("未解放")
                .font(.caption)
                .foregroundStyle(AppColor.muted)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(item.conditions) { condition in
                    HStack(spacing: 5) {
                        Image(systemName: condition.isSatisfied ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(condition.isSatisfied ? AppColor.success : AppColor.muted)
                        // 「あと何をすれば読めるか」なので、条件の文は本文色で読ませる。
                        Text(condition.text)
                            .foregroundStyle(AppColor.text)
                        if let progressText = condition.progressText {
                            Text(progressText)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.muted)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}
