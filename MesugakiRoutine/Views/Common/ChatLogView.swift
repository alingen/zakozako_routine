import SwiftUI
import UIKit

/// キャラクターとの会話ログ(LINE風の吹き出し)を表示する共通ビュー。
/// ルーティン実行画面・今日の会話・(将来の)小イベントで共有する。表示専用で、進行ロジックは持たない。
struct ChatLogView: View {
    let messages: [ConversationMessage]
    var isCharacterThinking: Bool = false

    private static let typingIndicatorID = "chat-typing-indicator"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if isCharacterThinking {
                        ChatBubble.typingIndicator
                            .id(Self.typingIndicatorID)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isCharacterThinking) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let targetID: AnyHashable? = isCharacterThinking ? Self.typingIndicatorID : messages.last?.id
        guard let targetID else { return }
        withAnimation {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }
}

/// 1メッセージぶんの吹き出し。キャラクターは左・アイコン付き、ユーザーは右。
/// `message.imageName` が非nilなら画像メッセージとして表示する(小イベント用)。
struct ChatBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .character {
                CharacterAvatar(size: 28)
                bubbleContent(background: .secondary.opacity(0.15))
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleContent(background: Color.accentColor.opacity(0.2))
            }
        }
    }

    @ViewBuilder
    private func bubbleContent(background: Color) -> some View {
        if let imageName = message.imageName {
            ChatImageBubble(imageName: imageName, caption: message.text)
        } else {
            bubbleText(message.text, background: background)
        }
    }

    /// キャラクターが入力中であることを示すインジケーター吹き出し。
    static var typingIndicator: some View {
        HStack(alignment: .bottom, spacing: 6) {
            CharacterAvatar(size: 28)
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
}

/// 画像メッセージの吹き出し。指定名の画像がAssetsに無ければプレースホルダを表示する
/// (本番画像は後から差し込める。MVPでは構造の確認を優先)。
struct ChatImageBubble: View {
    let imageName: String
    var caption: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            image
                .frame(maxWidth: 220, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var image: some View {
        if UIImage(named: imageName) != nil {
            Image(imageName)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.15))
                .frame(width: 200, height: 150)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.title)
                        Text(imageName)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
        }
    }
}

/// キャラクターアイコン(円形)。会話ログのあちこちで使うので共通化する。
struct CharacterAvatar: View {
    var size: CGFloat = 28

    var body: some View {
        Image("CharacterIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}
