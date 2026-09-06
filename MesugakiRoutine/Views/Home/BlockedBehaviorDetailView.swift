import SwiftUI

/// 「やらないこと」1件の編集シート。タイトルと上限を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (_ title: String, _ limitPeriod: HabitPeriod, _ limitCount: Int) -> Void

    @State private var title: String
    /// true: 完全にやめる(1日1回でも✕)。false: ペース・回数を自分で決める。
    @State private var isQuitCompletely: Bool
    @State private var limitPeriod: HabitPeriod
    @State private var limitCount: Int

    init(
        behavior: BlockedBehavior,
        onSave: @escaping (String, HabitPeriod, Int) -> Void
    ) {
        self.onSave = onSave
        _title = State(initialValue: behavior.title)
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
            }
            .navigationTitle("やらないことを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(
                            title,
                            isQuitCompletely ? .day : limitPeriod,
                            isQuitCompletely ? 1 : limitCount
                        )
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
