import SwiftUI

/// 弧で割合を表す円。用途によって意味は変わる:
/// - ルーティン: 「今日の達成量 / 目標量」。1.0 で塗りつぶし＋チェック(完了)。
/// - 今日の約束: 「期間内の消費回数 / 上限」。`showsCheckmarkWhenComplete: false` + 警告色で、
///   上限到達＝塗りつぶし(チェックは出さない = 達成ではなく注意)。
struct ProgressCircle: View {
    /// 0.0〜1.0。範囲外は丸める。
    let progress: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3
    /// 弧・塗りつぶしの色。
    var tint: Color = AppColor.primary
    /// 1.0 到達時にチェックマークを出すか。約束カードでは false(達成の意味にならないように)。
    var showsCheckmarkWhenComplete: Bool = true

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isComplete: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.border, lineWidth: lineWidth)

            if isComplete {
                Circle().fill(tint)
                if showsCheckmarkWhenComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.44, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: clamped)
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
