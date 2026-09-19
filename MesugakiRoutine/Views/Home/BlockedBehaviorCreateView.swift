import FamilyControls
import SwiftUI
import UIKit

/// 「やらないこと」の新規作成と編集で共用する入力画面。
struct BlockedBehaviorCreateView: View {
    private struct ScreenTimeAuthorizationAlert: Identifiable {
        let id = UUID()
        let message: String
        let offersSettingsAction: Bool
    }

    private enum CreationStep {
        case presetSelection
        case details
    }

    private enum DraftSource: Equatable {
        case custom
        case preset(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let behavior: BlockedBehavior?
    let onRequestScreenTimeAuthorization: () async throws -> Void
    let onSave: (BlockedBehaviorDraft) -> String?
    let onRequestDelete: (() -> Void)?

    @State private var creationStep: CreationStep = .presetSelection
    @State private var draftSource: DraftSource?
    @State private var draft = BlockedBehaviorDraft()
    @State private var isPresentingIconPicker = false
    @State private var isPresentingScreenTimePicker = false
    @State private var isRequestingScreenTimeAuthorization = false
    @State private var screenTimeAuthorizationRequestID: UUID?
    @State private var saveErrorMessage: String?
    @State private var screenTimeAuthorizationAlert: ScreenTimeAuthorizationAlert?

    init(
        behavior: BlockedBehavior? = nil,
        onRequestScreenTimeAuthorization: @escaping () async throws -> Void,
        onSave: @escaping (BlockedBehaviorDraft) -> String?,
        onRequestDelete: (() -> Void)? = nil
    ) {
        self.behavior = behavior
        self.onRequestScreenTimeAuthorization = onRequestScreenTimeAuthorization
        self.onSave = onSave
        self.onRequestDelete = onRequestDelete
        _creationStep = State(initialValue: behavior == nil ? .presetSelection : .details)
        _draftSource = State(initialValue: behavior == nil ? nil : .custom)
        _draft = State(initialValue: behavior.map(BlockedBehaviorDraft.init(behavior:)) ?? BlockedBehaviorDraft())
    }

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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEditing {
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
                get: { screenTimeAuthorizationAlert != nil },
                set: { if !$0 { screenTimeAuthorizationAlert = nil } }
            ),
            presenting: screenTimeAuthorizationAlert
        ) { alert in
            if alert.offersSettingsAction {
                Button("設定アプリを開く") {
                    openAppSettings()
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    private var isSelectingPreset: Bool {
        creationStep == .presetSelection
    }

    private var isEditing: Bool {
        behavior != nil
    }

    private var navigationTitle: String {
        if isEditing { return "やらないことを編集" }
        return isSelectingPreset ? "やらないことを追加" : "やらないことを確認"
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
                            if isRequestingScreenTimeAuthorization {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppColor.primary)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.muted)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingScreenTimeAuthorization)
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

            if let onRequestDelete {
                Section {
                    Button(role: .destructive, action: onRequestDelete) {
                        Text("削除する")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
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
            Text(isEditing ? "変更を保存" : "やらないことを保存")
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
        guard !isRequestingScreenTimeAuthorization else { return }

        let requestID = UUID()
        screenTimeAuthorizationRequestID = requestID
        isRequestingScreenTimeAuthorization = true

        Task { @MainActor in
            defer {
                if screenTimeAuthorizationRequestID == requestID {
                    screenTimeAuthorizationRequestID = nil
                    isRequestingScreenTimeAuthorization = false
                }
            }

            do {
                try await onRequestScreenTimeAuthorization()
                guard screenTimeAuthorizationRequestID == requestID,
                      creationStep == .details,
                      draft.trackingKind == .screenTime else { return }
                isPresentingScreenTimePicker = true
            } catch ScreenTimeMonitoringError.authorizationCanceled {
                // システムの許可画面を閉じた場合は、エラーを重ねずそのまま再操作できるようにする。
                return
            } catch let error as ScreenTimeMonitoringError {
                guard screenTimeAuthorizationRequestID == requestID else { return }
                screenTimeAuthorizationAlert = ScreenTimeAuthorizationAlert(
                    message: error.errorDescription ?? "設定からスクリーンタイムの許可を確認してください。",
                    offersSettingsAction: error.offersSettingsAction
                )
            } catch {
                guard screenTimeAuthorizationRequestID == requestID else { return }
                screenTimeAuthorizationAlert = ScreenTimeAuthorizationAlert(
                    message: "スクリーンタイムの許可を確認できませんでした。\n\(error.localizedDescription)",
                    offersSettingsAction: false
                )
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        BlockedBehaviorCreateView(
            onRequestScreenTimeAuthorization: {},
            onSave: { _ in nil }
        )
    }
}
