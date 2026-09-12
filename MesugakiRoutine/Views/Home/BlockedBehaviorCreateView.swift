import SwiftUI

/// プリセット選択から確認・保存までを扱う「やらないこと」の新規作成画面。
struct BlockedBehaviorCreateView: View {
    private enum CreationStep {
        case presetSelection
        case details
    }

    private enum DraftSource: Equatable {
        case custom
        case preset(String)
    }

    @Environment(\.dismiss) private var dismiss

    let onSave: (BlockedBehaviorDraft) -> Bool

    @State private var creationStep: CreationStep = .presetSelection
    @State private var draftSource: DraftSource?
    @State private var draft = BlockedBehaviorDraft()
    @State private var isPresentingIconPicker = false
    @State private var isShowingSaveError = false

    var body: some View {
        Group {
            if isSelectingPreset {
                BlockedBehaviorPresetSelectionView(
                    onSelectCustom: showCustomDetails,
                    onSelectPreset: showPresetDetails
                )
            } else {
                detailsForm
            }
        }
        .navigationTitle(isSelectingPreset ? "やらないことを追加" : "やらないことを確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isSelectingPreset {
                    Button("キャンセル") {
                        dismiss()
                    }
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            creationStep = .presetSelection
                        }
                    } label: {
                        Label("プリセット", systemImage: "chevron.left")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isSelectingPreset {
                saveButton
            }
        }
        .sheet(isPresented: $isPresentingIconPicker) {
            IconPickerView(selected: draft.iconName, icons: BlockedBehaviorIcon.all) { name in
                draft.iconName = name
            }
        }
        .alert("保存できませんでした", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("別の「やらないこと」が開始されていないか確認して、もう一度お試しください。")
        }
    }

    private var isSelectingPreset: Bool {
        creationStep == .presetSelection
    }

    private var detailsForm: some View {
        Form {
            Section("やらないこと") {
                TextField("例: YouTubeを見ない", text: $draft.title)
            }

            Section("アイコン") {
                Button {
                    isPresentingIconPicker = true
                } label: {
                    HStack {
                        Text("アイコン")
                            .foregroundStyle(AppColor.text)
                        Spacer()
                        if let iconName = draft.iconName {
                            Image(systemName: iconName)
                                .foregroundStyle(AppColor.primary)
                        } else {
                            Text("なし")
                                .foregroundStyle(AppColor.muted)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                Picker("上限", selection: $draft.isQuitCompletely) {
                    Text("完全にやめる").tag(true)
                    Text("回数を決める").tag(false)
                }

                if !draft.isQuitCompletely {
                    Picker("ペース", selection: $draft.limitPeriod) {
                        ForEach(HabitPeriod.allCases) { period in
                            Text(period.pickerLabel).tag(period)
                        }
                    }
                    Stepper(
                        "\(draft.limitPeriod.pickerLabel) \(draft.limitCount) 回で✕",
                        value: $draft.limitCount,
                        in: 1...50
                    )
                }
            } header: {
                Text("上限設定")
            } footer: {
                Text(draft.isQuitCompletely
                     ? "1回でもやってしまったら、その日は✕になります。"
                     : "設定した回数に達すると✕になり、その期間は失敗扱いです。")
            }
        }
    }

    private var saveButton: some View {
        Button {
            if onSave(draft) {
                dismiss()
            } else {
                isShowingSaveError = true
            }
        } label: {
            Text("やらないことを保存")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.primary)
        .disabled(!draft.canSave)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColor.background)
    }

    private func showCustomDetails() {
        if draftSource != .custom {
            draft.reset()
        }
        draftSource = .custom
        showDetails()
    }

    private func showPresetDetails(_ preset: BlockedBehaviorPreset) {
        let selectedSource = DraftSource.preset(preset.id)
        if draftSource != selectedSource {
            draft.apply(preset)
        }
        draftSource = selectedSource
        showDetails()
    }

    private func showDetails() {
        withAnimation(.easeInOut(duration: 0.2)) {
            creationStep = .details
        }
    }
}

#Preview {
    NavigationStack {
        BlockedBehaviorCreateView { _ in true }
    }
}
