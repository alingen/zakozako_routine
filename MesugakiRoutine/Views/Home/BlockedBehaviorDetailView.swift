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
                    Stepper("\(limitPeriod.displayName) \(limitCount) 回まで", value: $limitCount, in: 0...50)
                } header: {
                    Text("回数制限")
                } footer: {
                    Text("カードをタップするたびに1回消費します。この回数以内に収まった日が「達成」としてカウントされます。0回なら1回でもアウトです。")
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
