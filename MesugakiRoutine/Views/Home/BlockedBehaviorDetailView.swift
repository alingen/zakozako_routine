import SwiftUI

/// 「今日の約束」1件の編集シート。タイトルと回数制限を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (_ title: String, _ limitPeriod: HabitPeriod, _ limitCount: Int) -> Void

    @State private var title: String
    @State private var limitPeriod: HabitPeriod
    @State private var limitCount: Int

    init(
        behavior: BlockedBehavior,
        onSave: @escaping (String, HabitPeriod, Int) -> Void
    ) {
        self.onSave = onSave
        _title = State(initialValue: behavior.title)
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
                    Picker("ペース", selection: $limitPeriod) {
                        ForEach(HabitPeriod.allCases) { period in
                            Text(period.pickerLabel).tag(period)
                        }
                    }
                    Stepper("\(limitPeriod.pickerLabel) \(limitCount) 回で✕", value: $limitCount, in: 1...50)
                } header: {
                    Text("回数制限")
                } footer: {
                    Text("チェックボックスは満タンからスタートし、カードをタップするたびに1つ減ります。全部なくなると✕になり、その期間は失敗扱いです。")
                }
            }
            .navigationTitle("やらないことを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(title, limitPeriod, limitCount)
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
