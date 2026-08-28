import SwiftUI
import UIKit

/// 大イベントのギャルゲー風画面。背景 + 立ち絵 + テキストウィンドウ + 名前 + 選択肢。
/// 一枚絵(CG)は前面に重ねて表示する。MVPなので演出は最小限で、タップ送りが正常に動くことを優先する。
struct BigEventView: View {
    let eventId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BigEventViewModel()

    /// 直近で指定された背景/立ち絵(メッセージ側が nil の間は維持する)。
    @State private var background: String?
    @State private var portrait: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backgroundLayer
            portraitLayer
            cgLayer
            VStack {
                Spacer()
                dialogueArea
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("とじる") { dismiss() }
                    .tint(.white)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.player?.pendingChoices == nil else { return }
            Task { await viewModel.advance() }
        }
        .task {
            viewModel.configure(context: modelContext, eventId: eventId)
            background = viewModel.defaultBackground
            await viewModel.start()
            syncScene()
        }
        .onChange(of: viewModel.player?.currentMessage) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) { syncScene() }
        }
    }

    /// メッセージ側で背景/立ち絵が指定されていれば取り込む(nilの間は現状維持)。
    private func syncScene() {
        guard let message = viewModel.player?.currentMessage else { return }
        if let bg = message.background { background = bg }
        if let p = message.portrait { portrait = p }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let background, UIImage(named: background) != nil {
            Image(background)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.13, blue: 0.22), Color(red: 0.28, green: 0.20, blue: 0.32)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var portraitLayer: some View {
        if let portrait, UIImage(named: portrait) != nil {
            Image(portrait)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var cgLayer: some View {
        if let cg = viewModel.player?.currentMessage?.cg, UIImage(named: cg) != nil {
            Image(cg)
                .resizable()
                .scaledToFit()
                .padding()
                .transition(.opacity)
        }
    }

    private var dialogueArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let choices = viewModel.player?.pendingChoices, !choices.isEmpty {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        Task { await viewModel.selectChoice(choice) }
                    } label: {
                        Text(choice.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
            } else {
                if let name = viewModel.speakerName(for: viewModel.player?.currentMessage) {
                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.pink.opacity(0.85), in: Capsule())
                }
                Text(viewModel.player?.currentText ?? "")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)

                if viewModel.player?.isFinished == true {
                    Button("とじる") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("▼ タップで進む")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15)))
        .padding(12)
    }
}
