import SwiftUI
import SwiftData

/// 小イベントの会話画面。今日の会話と同じLINE風UI(`ChatLogView`)と再生エンジン(`ScriptPlayer`)を使う。
/// 大イベント(ギャルゲー風の専用画面)は STEP 6 で別Viewとして追加する。
struct EventConversationView: View {
    let eventId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = EventConversationViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let player = viewModel.player {
                ChatLogView(messages: player.messages, isCharacterThinking: player.isCharacterTyping)
            } else {
                Spacer()
            }
            Divider()
            footer
        }
        .background(AppColor.background)
        .navigationTitle(viewModel.eventTitle.isEmpty ? "イベント" : viewModel.eventTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.player?.isFinished != true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("とじる") { dismiss() }
            }
        }
        .task {
            viewModel.configure(context: modelContext, eventId: eventId)
            await viewModel.start()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let choices = viewModel.player?.pendingChoices, !choices.isEmpty {
            VStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button(choice.text) {
                        Task { await viewModel.selectChoice(choice) }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        } else if viewModel.player?.isFinished == true {
            Button("とじる") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
}
