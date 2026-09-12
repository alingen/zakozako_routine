import SwiftUI

/// 「やらないこと」1件の編集シート。タイトルと上限を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (_ title: String, _ iconName: String?, _ limitPeriod: HabitPeriod, _ limitCount: Int) -> Bool
    let onDelete: () -> Bool

    @State private var title: String
    @State private var iconName: String?
    /// true: 完全にやめる(1日1回でも✕)。false: ペース・回数を自分で決める。
    @State private var isQuitCompletely: Bool
    @State private var limitPeriod: HabitPeriod
    @State private var limitCount: Int
    @State private var isPresentingIconPicker = false
    @State private var isPresentingDeleteConfirm = false
    @State private var isShowingSaveError = false
    @State private var isShowingDeleteError = false

    init(
        behavior: BlockedBehavior,
        onSave: @escaping (String, String?, HabitPeriod, Int) -> Bool,
        onDelete: @escaping () -> Bool
    ) {
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: behavior.title)
        _iconName = State(initialValue: behavior.iconName)
        _isQuitCompletely = State(initialValue: behavior.limitPeriod == .day && behavior.limitCount == 1)
        _limitPeriod = State(initialValue: behavior.limitPeriod)
        _limitCount = State(initialValue: behavior.limitCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("やらないこと") {
                    TextField("例: YouTubeを見ない", text: $title)
                }

                Section("アイコン") {
                    Button {
                        isPresentingIconPicker = true
                    } label: {
                        HStack {
                            Text("アイコン")
                                .foregroundStyle(AppColor.text)
                            Spacer()
                            if let iconName {
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
                    Picker("上限", selection: $isQuitCompletely) {
                        Text("完全にやめる").tag(true)
                        Text("回数を決める").tag(false)
                    }
                    if !isQuitCompletely {
                        Picker("ペース", selection: $limitPeriod) {
                            ForEach(HabitPeriod.allCases) { period in
                                Text(period.pickerLabel).tag(period)
                            }
                        }
                        Stepper("\(limitPeriod.pickerLabel) \(limitCount) 回で✕", value: $limitCount, in: 1...50)
                    }
                } header: {
                    Text("上限設定")
                } footer: {
                    Text(isQuitCompletely
                         ? "1回でもやってしまったら、その日は✕になります。"
                         : "チェックボックスは満タンからスタートし、カードをタップするたびに1つ減ります。全部なくなると✕になり、その期間は失敗扱いです。")
                }

                Section {
                    Button("このやらないことを削除", role: .destructive) {
                        isPresentingDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("やらないことを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if onSave(
                            title,
                            iconName,
                            isQuitCompletely ? .day : limitPeriod,
                            isQuitCompletely ? 1 : limitCount
                        ) {
                            dismiss()
                        } else {
                            isShowingSaveError = true
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isPresentingIconPicker) {
            IconPickerView(selected: iconName, icons: BlockedBehaviorIcon.all) { name in
                iconName = name
            }
        }
        .alert("保存できませんでした", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
        .confirmationDialog(
            "このやらないことを削除しますか？",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                if onDelete() {
                    dismiss()
                } else {
                    isShowingDeleteError = true
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("削除できませんでした", isPresented: $isShowingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
    }
}
