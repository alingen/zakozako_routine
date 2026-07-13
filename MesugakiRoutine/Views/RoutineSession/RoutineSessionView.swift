import SwiftUI

/// ルーティン実行画面。
///
/// この View はテキスト/ボタン操作のUIに徹し、進行ロジックは一切持たない。
/// 将来ここが音声Live画面(OpenAI Realtime API等)に差し替わる際は、
/// RoutineSessionViewModel より下のレイヤーはそのまま再利用し、この View だけを置き換える想定。
struct RoutineSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RoutineSessionViewModel
    @State private var isPresentingExitConfirm = false

    init(routine: Routine) {
        _viewModel = State(initialValue: RoutineSessionViewModel(routine: routine))
    }

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            conversationLog
            Divider()
            inputArea
        }
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
        .task {
            viewModel.configure(context: modelContext)
        }
        .onDisappear {
            viewModel.stopVoiceMode()
        }
    }

    @ViewBuilder
    private var stepHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            characterAvatar(size: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.characterName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                if let progress = viewModel.progress {
                    if let current = progress.currentStep {
                        Text(current.title)
                            .font(.title2.bold())
                        Text("残り \(progress.remainingSteps.count) ステップ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private func characterAvatar(size: CGFloat) -> some View {
        Image("CharacterIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }

    private var conversationLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if viewModel.isCharacterThinking {
                        typingIndicatorBubble
                            .id("typing-indicator")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isCharacterThinking) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let targetId: AnyHashable? = viewModel.isCharacterThinking ? "typing-indicator" : viewModel.messages.last?.id
        guard let targetId else { return }
        withAnimation {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
    }

    private func messageBubble(_ message: ConversationMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .character {
                characterAvatar(size: 28)
                bubbleText(message.text, background: .secondary.opacity(0.15))
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleText(message.text, background: Color.accentColor.opacity(0.2))
            }
        }
    }

    private var typingIndicatorBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            characterAvatar(size: 28)
            TypingIndicatorView()
                .padding(10)
                .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 40)
        }
    }

    private func bubbleText(_ text: String, background: Color) -> some View {
        Text(text)
            .padding(10)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 音声会話モードのオン/オフと状態表示。見た目の作り込みは別途行う前提の、動作確認用の最小限のUI。
    @ViewBuilder
    private var voiceControls: some View {
        HStack(spacing: 8) {
            Button(isVoiceActive ? "🛑 音声会話を終了" : "🎙️ 音声会話を開始") {
                Task {
                    if isVoiceActive {
                        viewModel.stopVoiceMode()
                    } else {
                        await viewModel.startVoiceMode()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text(voiceStateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if !viewModel.livePartialUserText.isEmpty {
            Text(viewModel.livePartialUserText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isVoiceActive: Bool {
        if case .idle = viewModel.voiceState { return false }
        return true
    }

    private var voiceStateLabel: String {
        switch viewModel.voiceState {
        case .idle: return ""
        case .listening: return "聞いています…"
        case .thinking: return "考え中…"
        case .speaking: return "話しています…"
        case .error(let message): return "エラー: \(message)"
        }
    }

    private var inputArea: some View {
        VStack(spacing: 12) {
            if let progress = viewModel.progress, !progress.isFinished {
                voiceControls
                HStack(spacing: 8) {
                    actionButton("できた") { await viewModel.complete() }
                    actionButton("できなかった") { await viewModel.fail() }
                    actionButton("助けて") { await viewModel.askForHelp() }
                }
                HStack {
                    TextField("メッセージを入力", text: $viewModel.inputText)
                        .textFieldStyle(.roundedBorder)
                    Button("送信") {
                        Task { await viewModel.submitFreeText() }
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if viewModel.progress?.isFinished == true {
                if viewModel.isFreeTalkActive {
                    voiceControls
                    HStack {
                        TextField("メッセージを入力", text: $viewModel.inputText)
                            .textFieldStyle(.roundedBorder)
                        Button("送信") {
                            Task { await viewModel.sendFreeTalkMessage() }
                        }
                        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button("今日は終わる") {
                        viewModel.finishSession()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 12) {
                        Button("少し話す") {
                            Task { await viewModel.startFreeTalk() }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("今日は終わる") {
                            viewModel.finishSession()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
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
