import SwiftUI

/// キャラクターが返答を考えている間に表示する、チャットアプリでおなじみの「入力中」ドットアニメーション。
struct TypingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .foregroundStyle(.secondary)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    TypingIndicatorView()
        .padding()
}
