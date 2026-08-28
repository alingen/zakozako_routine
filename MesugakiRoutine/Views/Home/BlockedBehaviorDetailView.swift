import SwiftUI

/// 「やらないこと」1件の詳細設定シート。検出ワード・時間帯・理由・代替行動を編集する。
struct BlockedBehaviorDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let behaviorTitle: String
    let onSave: (
        _ reason: String,
        _ alternativeAction: String,
        _ triggerText: String,
        _ useTimeWindow: Bool,
        _ startTime: Date,
        _ endTime: Date
    ) -> Void

    @State private var reason: String
    @State private var alternativeAction: String
    @State private var triggerText: String
    @State private var useTimeWindow: Bool
    @State private var startTime: Date
    @State private var endTime: Date

    init(behavior: BlockedBehavior, onSave: @escaping (String, String, String, Bool, Date, Date) -> Void) {
        self.behaviorTitle = behavior.title
        self.onSave = onSave
        _reason = State(initialValue: behavior.reason)
        _alternativeAction = State(initialValue: behavior.alternativeAction)
        _triggerText = State(initialValue: behavior.triggerText)
        _useTimeWindow = State(initialValue: behavior.activeStartMinute != nil && behavior.activeEndMinute != nil)
        _startTime = State(initialValue: BlockedBehavior.date(fromMinutes: behavior.activeStartMinute ?? 7 * 60))
        _endTime = State(initialValue: BlockedBehavior.date(fromMinutes: behavior.activeEndMinute ?? 9 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: 仕事をさぼらないため", text: $reason)
                } header: {
                    Text("やめる理由")
                } footer: {
                    Text("「負けそう」ボタンを押した時、キャラクターがこの理由を引き合いに出してからかいます。")
                }

                Section {
                    TextField("例: 音楽をかける", text: $alternativeAction)
                } header: {
                    Text("代替行動")
                } footer: {
                    Text("反応するときに、この代わりの行動を勧めます。空欄でも構いません。")
                }

                Section {
                    TextField("例: YouTube", text: $triggerText)
                } header: {
                    Text("検出ワード")
                } footer: {
                    Text("会話中にこの言葉が含まれていたら「やらないこと」として反応します。")
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
                        onSave(reason, alternativeAction, triggerText, useTimeWindow, startTime, endTime)
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
