import SwiftUI

/// ルーティン実行画面。
///
/// この View はテキスト/ボタン操作のUIに徹し、進行ロジックは一切持たない。
struct RoutineSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RoutineSessionViewModel
    @State private var isPresentingExitConfirm = false
    @State private var isPresentingTodayConversation = false
    /// 完了体験を閉じた後に「今日の会話」へ進むかどうか(fullScreenCover と sheet の二重表示を避けるため
    /// cover の onDismiss で sheet を出す)。
    @State private var startConversationAfterCompletion = false
    @FocusState private var isInputFocused: Bool

    init(routine: Routine) {
        _viewModel = State(initialValue: RoutineSessionViewModel(routine: routine))
    }

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            ChatLogView(messages: viewModel.messages, isCharacterThinking: viewModel.isCharacterThinking)
            Divider()
            inputArea
        }
        .background(AppColor.background)
        .navigationTitle(viewModel.routine.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("終了") {
                    isPresentingExitConfirm = true
                }
            }
        }
        .confirmationDialog("ルーティンを終了しますか？", isPresented: $isPresentingExitConfirm, titleVisibility: .visible) {
            Button("終了する", role: .destructive) {
                viewModel.finishSession()
                dismiss()
            }
            Button("続ける", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingTodayConversation, onDismiss: {
            // 今日の会話を終えたら(または閉じたら)ルーティン画面も閉じてホームへ戻す。
            viewModel.finishSession()
            dismiss()
        }) {
            NavigationStack {
                TodayConversationView()
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { viewModel.completionContext },
                set: { if $0 == nil { viewModel.clearCompletion() } }
            ),
            onDismiss: {
                // 完了体験を閉じた後の遷移はここに集約する。
                if startConversationAfterCompletion {
                    startConversationAfterCompletion = false
                    isPresentingTodayConversation = true
                } else {
                    viewModel.finishSession()
                    dismiss()
                }
            }
        ) { context in
            RoutineCompletionPresentation(
                context: context,
                onStartTodayConversation: {
                    startConversationAfterCompletion = true
                    viewModel.clearCompletion()
                },
                onFinish: {
                    viewModel.clearCompletion()
                }
            )
        }
        .task {
            viewModel.configure(context: modelContext)
        }
    }

    @ViewBuilder
    private var stepHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            CharacterAvatar(size: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.characterName)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.muted)

                if let progress = viewModel.progress {
                    if let current = progress.currentStep {
                        Text(current.title)
                            .font(.title2.bold())
                        Text("残り \(progress.remainingSteps.count) ステップ")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    } else {
                        Text(progress.isFinished ? "ルーティン完了！" : "準備中…")
                            .font(.title2.bold())
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var inputArea: some View {
        VStack(spacing: 12) {
            if let progress = viewModel.progress, !progress.isFinished {
                HStack(spacing: 8) {
                    actionButton("できた") { await viewModel.complete() }
                    actionButton("できなかった") { await viewModel.fail() }
                    actionButton("助けて") { await viewModel.askForHelp() }
                }
                HStack {
                    TextField("メッセージを入力", text: $viewModel.inputText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isInputFocused)
                    Button("送信") {
                        isInputFocused = false
                        Task { await viewModel.submitFreeText() }
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if viewModel.progress?.isFinished == true {
                // 完了時の導線は RoutineCompletionPresentation(fullScreenCover)へ移動。
                Text("ルーティン完了！")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) {
            Task { await action() }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let routine = Routine(title: "朝ルーティン", type: .morning)
    return NavigationStack {
        RoutineSessionView(routine: routine)
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self, CharacterPreset.self, BlockedBehavior.self], inMemory: true)
}
