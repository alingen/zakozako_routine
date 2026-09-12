import SwiftUI

/// 新規作成時に表示する、「やらないこと」のカスタム入力とプリセット選択画面。
struct BlockedBehaviorPresetSelectionView: View {
    let presets: [BlockedBehaviorPreset]
    let onSelectCustom: () -> Void
    let onSelectPreset: (BlockedBehaviorPreset) -> Void

    @State private var searchText = ""

    init(
        presets: [BlockedBehaviorPreset] = BlockedBehaviorPreset.all,
        onSelectCustom: @escaping () -> Void,
        onSelectPreset: @escaping (BlockedBehaviorPreset) -> Void
    ) {
        self.presets = presets
        self.onSelectCustom = onSelectCustom
        self.onSelectPreset = onSelectPreset
    }

    private var filteredPresets: [BlockedBehaviorPreset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return presets }
        return presets.filter { $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            Section {
                Text("やめたいことを選ぶと、タイトル・アイコン・上限を自動で入力します。内容は保存前に変更できます。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            }
            .listRowBackground(Color.clear)

            Section("自由に作る") {
                selectionButton(
                    title: "カスタム",
                    subtitle: "内容を自由に入力",
                    iconName: "square.and.pencil",
                    accessibilityHint: "空の入力画面を開きます",
                    action: onSelectCustom
                )
            }
            .appCardRow()

            Section("プリセットから選ぶ") {
                if filteredPresets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                        Text("プリセットが見つかりません")
                            .font(.headline)
                        Text("カスタムから自由に作成できます")
                            .font(.footnote)
                    }
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(filteredPresets) { preset in
                        selectionButton(
                            title: preset.title,
                            iconName: preset.iconName,
                            accessibilityHint: "内容を入力済みにして確認画面を開きます"
                        ) {
                            onSelectPreset(preset)
                        }
                    }
                }
            }
            .appCardRow()
        }
        .listStyle(.insetGrouped)
        .appScreenBackground()
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "プリセットを検索"
        )
    }

    private func selectionButton(
        title: String,
        subtitle: String? = nil,
        iconName: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 46, height: 46)
                    .background(AppColor.primarySoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.leading)

                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(AppColor.muted)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint)
    }
}

#Preview {
    NavigationStack {
        BlockedBehaviorPresetSelectionView(
            onSelectCustom: {},
            onSelectPreset: { _ in }
        )
        .navigationTitle("やらないことを追加")
        .navigationBarTitleDisplayMode(.inline)
    }
}
