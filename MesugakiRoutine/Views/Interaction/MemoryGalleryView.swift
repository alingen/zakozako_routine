import SwiftUI

struct MemoryGalleryView: View {
    let memories: [StoryMemoryPresentation]
    @State private var selectedMemory: StoryMemoryPresentation?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            if memories.isEmpty {
                ContentUnavailableView(
                    "まだ思い出がありません",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("CGのあるストーリーが追加されるとここに並びます")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(memories) { memory in
                        Button {
                            guard memory.isUnlocked else { return }
                            selectedMemory = memory
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    StoryAssetView(
                                        assetID: memory.isUnlocked ? memory.assetId : nil,
                                        purpose: .cg,
                                        contentMode: .fill,
                                        cornerRadius: 13
                                    )
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(4 / 3, contentMode: .fit)
                                    .saturation(memory.isUnlocked ? 1 : 0)

                                    if !memory.isUnlocked {
                                        Color.black.opacity(0.18)
                                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        Image(systemName: "lock.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                    }
                                }

                                Text(memory.isUnlocked ? memory.title : "？？？")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(memory.isUnlocked ? AppColor.text : AppColor.muted)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppColor.border)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(memory.isUnlocked ? "全画面で表示します" : "ストーリーを完了すると解放されます")
                    }
                }
                .padding(16)
            }
        }
        .background(AppColor.background)
        .navigationTitle("思い出")
        .fullScreenCover(item: $selectedMemory) { memory in
            MemoryFullscreenView(memory: memory) {
                selectedMemory = nil
            }
        }
    }
}
private struct MemoryFullscreenView: View {
    let memory: StoryMemoryPresentation
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            StoryAssetView(assetID: memory.assetId, purpose: .cg, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 54)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.58), in: Circle())
            }
            .padding()
            .accessibilityLabel("閉じる")
        }
    }
}
