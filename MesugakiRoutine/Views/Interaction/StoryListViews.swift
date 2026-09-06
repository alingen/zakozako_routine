import SwiftUI

struct StoryCatalogView: View {
    let mainChapters: [StoryChapterPresentation]
    let subChapters: [StoryChapterPresentation]
    let onOpen: (String) -> Void

    @State private var category: StoryCategory = .main

    private var chapters: [StoryChapterPresentation] {
        category == .main ? mainChapters : subChapters
    }

    var body: some View {
        List {
            Section {
                Picker("ストーリー区分", selection: $category) {
                    Text("メイン").tag(StoryCategory.main)
                    Text("サブ").tag(StoryCategory.sub)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .appCardRow()

            if chapters.isEmpty {
                ContentUnavailableView(
                    "まだストーリーがありません",
                    systemImage: "book.closed",
                    description: Text("追加されたストーリーはここに表示されます")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(chapters) { chapter in
                    Section(chapter.title) {
                        ForEach(chapter.stories) { story in
                            StoryListRow(item: story) {
                                onOpen(story.id)
                            }
                        }
                    }
                    .appCardRow()
                }
            }
        }
        .appScreenBackground()
        .navigationTitle("ストーリー")
    }
}

private struct StoryListRow: View {
    let item: StoryListItemPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                StoryAssetView(
                    assetID: item.backgroundAssetId,
                    purpose: .background,
                    contentMode: .fill,
                    cornerRadius: 10
                )
                .frame(width: 68, height: 68)
                .saturation(item.isUnlocked ? 1 : 0)
                .opacity(item.isUnlocked ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        if let episodeOrder = item.episodeOrder {
                            Text("第\(episodeOrder)話")
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
                        } else if item.isRead {
                            Label("既読", systemImage: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(AppColor.success)
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
                Image(systemName: item.isUnlocked ? "chevron.right" : "lock.fill")
                    .foregroundStyle(item.isUnlocked ? AppColor.primary : AppColor.muted)
                    .padding(.top, 22)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isUnlocked)
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
                        Text(condition.text)
                        if let progressText = condition.progressText {
                            Text(progressText)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(AppColor.muted)
                }
            }
        }
    }
}
