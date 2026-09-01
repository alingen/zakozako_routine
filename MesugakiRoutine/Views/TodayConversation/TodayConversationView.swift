import SwiftUI
import SwiftData

/// 「今日の会話」画面。ルーティン完了後の導線から開かれる。
///
/// LINEのトーク画面のような見た目で、事前に用意した台本を再生するだけ(AIは使わない)。
/// 会話を終えた時点で、解放済み・未完了のイベントがあれば「話したいことがあるみたい」と予告する。
struct TodayConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = TodayConversationViewModel()
    @State private var presentedEvent: EventDefinition?

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
        .navigationTitle("今日の会話  Day \(viewModel.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.player?.isFinished != true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("とじる") { dismiss() }
            }
        }
        .task {
            viewModel.configure(context: modelContext)
            await viewModel.start()
        }
        .fullScreenCover(item: $presentedEvent, onDismiss: { dismiss() }) { event in
            NavigationStack {
                EventPlayerView(event: event)
            }
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
            if let event = viewModel.pendingEvent {
                VStack(spacing: 10) {
                    Text("\(viewModel.characterName)が話したいことがあるみたい")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Button("話を聞く") { presentedEvent = event }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Button("あとにする") {
                            viewModel.deferPendingEvent()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            } else {
                Button("会話を終える") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

#Preview {
    NavigationStack {
        TodayConversationView()
    }
    .modelContainer(
        for: [
            Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self,
            CharacterPreset.self, BlockedBehavior.self, TrustState.self,
            UserProfileFact.self, FreeTalkTopicProgress.self, DailyConversationState.self,
            EventProgress.self,
            RelationshipState.self,
        ],
        inMemory: true
    )
}
