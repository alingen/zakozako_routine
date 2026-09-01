import SwiftUI

/// 「今日の約束」1件の編集シート。タイトルと回数制限を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (_ title: String, _ limitPeriod: BlockedBehaviorLimitPeriod, _ limitCount: Int) -> Void

    @State private var title: String
    @State private var limitPeriod: BlockedBehaviorLimitPeriod
    @State private var limitCount: Int

    init(
        behavior: BlockedBehavior,
        onSave: @escaping (String, BlockedBehaviorLimitPeriod, Int) -> Void
    ) {
        self.onSave = onSave
        _title = State(initialValue: behavior.title)
        _limitPeriod = State(initialValue: behavior.limitPeriod)
        _limitCount = State(initialValue: behavior.limitCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("約束") {
                    TextField("例: YouTubeを見ない", text: $title)
                }

                Section {
                    Picker("ペース", selection: $limitPeriod) {
                        ForEach(BlockedBehaviorLimitPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    Stepper("\(limitPeriod.displayName) \(limitCount) 回で✕", value: $limitCount, in: 1...50)
                } header: {
                    Text("回数制限")
                } footer: {
                    Text("チェックボックスは満タンからスタートし、カードをタップするたびに1つ減ります。全部なくなると✕になり、その期間は失敗扱いです。")
                }
            }
            .navigationTitle("約束を編集")
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
