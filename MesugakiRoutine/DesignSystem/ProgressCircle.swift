import SwiftUI

/// 「今日の達成量 / 今日の目標量」を表す進捗円。
/// - 0.0 → 空円(枠線のみ)
/// - 0.0〜1.0 → 上端から時計回りに弧が伸びる
/// - 1.0 → 塗りつぶし + チェック(完了状態)
///
/// 過去30日の達成率などではなく、あくまで「今日どれだけ進んだか」を渡すこと。
struct ProgressCircle: View {
    /// 0.0〜1.0。範囲外は丸める。
    let progress: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isComplete: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.border, lineWidth: lineWidth)

            if isComplete {
                Circle().fill(AppColor.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AppColor.primary,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: clamped)
        .accessibilityLabel("今日の進捗")
        .accessibilityValue("\(Int((clamped * 100).rounded()))パーセント")
    }
}

#Preview {
    HStack(spacing: 20) {
        ProgressCircle(progress: 0)
        ProgressCircle(progress: 0.25)
        ProgressCircle(progress: 0.5)
        ProgressCircle(progress: 0.75)
        ProgressCircle(progress: 1)
    }
    .padding()
}
