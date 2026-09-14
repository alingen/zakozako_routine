import FamilyControls
import SwiftUI

/// プリセットまたはカスタム入力から、内容をすべて決めて保存する「やらないこと」の新規作成画面。
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

    let onSave: (BlockedBehaviorDraft) -> String?

    @State private var creationStep: CreationStep = .presetSelection
    @State private var draftSource: DraftSource?
    @State private var draft = BlockedBehaviorDraft()
    @State private var isPresentingIconPicker = false
    @State private var isPresentingScreenTimePicker = false
    @State private var saveErrorMessage: String?
    @State private var screenTimeAuthorizationError: String?

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
        .familyActivityPicker(
            headerText: "使いすぎを計測するアプリやカテゴリを選んでください",
            footerText: "選んだ対象の合計使用時間が、設定した上限を超えると失敗になります。",
            isPresented: $isPresentingScreenTimePicker,
            selection: $draft.screenTimeSelection
        )
        .alert(
            "保存できませんでした",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "もう一度お試しください。")
        }
        .alert(
            "スクリーンタイムを利用できません",
            isPresented: Binding(
                get: { screenTimeAuthorizationError != nil },
                set: { if !$0 { screenTimeAuthorizationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                screenTimeAuthorizationError = nil
            }
        } message: {
            Text(screenTimeAuthorizationError ?? "設定からスクリーンタイムの許可を確認してください。")
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

            if draft.trackingKind == .screenTime {
                Section("スクリーンタイム") {
                    Button {
                        requestScreenTimeAuthorization()
                    } label: {
                        HStack {
                            Label("対象アプリ", systemImage: "iphone")
                                .foregroundStyle(AppColor.text)
                            Spacer()
                            Text(screenTimeTargetSummary)
                                .foregroundStyle(
                                    draft.screenTimeTargetCount == 0
                                        ? AppColor.error
                                        : AppColor.muted
                                )
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Stepper(
                        value: $draft.screenTimeLimitMinutes,
                        in: 5...720,
                        step: 5
                    ) {
                        LabeledContent(
                            "時間上限",
                            value: formattedDuration(draft.screenTimeLimitMinutes)
                        )
                        .foregroundStyle(AppColor.text)
                    }
                } header: {
                    Text("上限設定")
                } footer: {
                    Text(
                        "選択した対象の合計使用時間が\(formattedDuration(draft.screenTimeLimitMinutes))を超えると、その日は自動で失敗になります。設定後の使用状況をiOSが自動で集計します。"
                    )
                }
            } else {
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
                            "\(draft.limitPeriod.pickerLabel) \(draft.limitCount) 回で失敗",
                            value: $draft.limitCount,
                            in: 1...50
                        )
                    }
                } header: {
                    Text("上限設定")
                } footer: {
                    Text(draft.isQuitCompletely
                         ? "1回でもやってしまったら、その日は失敗になります。"
                         : "設定した回数に達すると、その期間は失敗になります。")
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            if let errorMessage = onSave(draft) {
                saveErrorMessage = errorMessage
            } else {
                dismiss()
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

    private var screenTimeTargetSummary: String {
        draft.screenTimeTargetCount == 0
            ? "未選択"
            : "\(draft.screenTimeTargetCount)項目"
    }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        switch (hours, remainingMinutes) {
        case (0, _):
            return "\(remainingMinutes)分"
        case (_, 0):
            return "\(hours)時間"
        default:
            return "\(hours)時間\(remainingMinutes)分"
        }
    }

    private func requestScreenTimeAuthorization() {
        Task { @MainActor in
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                isPresentingScreenTimePicker = true
            } catch {
                screenTimeAuthorizationError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        BlockedBehaviorCreateView { _ in nil }
    }
}
