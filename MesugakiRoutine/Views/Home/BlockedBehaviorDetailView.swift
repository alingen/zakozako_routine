import SwiftUI

/// 「やらないこと」1件の詳細設定シート。検出ワード・時間帯・代替行動を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let behaviorTitle: String
    let onSave: (
        _ triggerText: String,
        _ alternativeAction: String,
        _ useTimeWindow: Bool,
        _ startTime: Date,
        _ endTime: Date
    ) -> Void

    @State private var triggerText: String
    @State private var alternativeAction: String
    @State private var useTimeWindow: Bool
    @State private var startTime: Date
    @State private var endTime: Date

    init(behavior: BlockedBehavior, onSave: @escaping (String, String, Bool, Date, Date) -> Void) {
        self.behaviorTitle = behavior.title
        self.onSave = onSave
        _triggerText = State(initialValue: behavior.triggerText)
        _alternativeAction = State(initialValue: behavior.alternativeAction)
        _useTimeWindow = State(initialValue: behavior.activeStartMinute != nil && behavior.activeEndMinute != nil)
        _startTime = State(initialValue: BlockedBehavior.date(fromMinutes: behavior.activeStartMinute ?? 7 * 60))
        _endTime = State(initialValue: BlockedBehavior.date(fromMinutes: behavior.activeEndMinute ?? 9 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: YouTube", text: $triggerText)
                } header: {
                    Text("検出ワード")
                } footer: {
                    Text("会話中にこの言葉が含まれていたら「やらないこと」として反応します。")
                }

                Section {
                    TextField("例: 水を飲む", text: $alternativeAction)
                } header: {
                    Text("代替行動")
                } footer: {
                    Text("反応するときに、この代わりの行動を勧めます。空欄でも構いません。")
                }

                Section {
                    Toggle("時間帯を指定する", isOn: $useTimeWindow)
                    if useTimeWindow {
                        DatePicker("開始", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("時間帯")
                } footer: {
                    Text("指定した時間帯の間だけ検出します。指定しなければ常に検出します。")
                }
            }
            .navigationTitle(behaviorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(triggerText, alternativeAction, useTimeWindow, startTime, endTime)
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
