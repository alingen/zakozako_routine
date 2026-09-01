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
    /// 「失敗」状態。true のとき、進捗に関わらず薄い円 + ✕ を表示する(今日の約束の上限到達)。
    var failed: Bool = false
    /// 円の中に表示する SF Symbol。
    /// - 未完了: 枠の中にアイコンを `tint` 色で表示(背景は透明=白)。
    /// - 完了: 背景 `tint` / アイコン白 に反転。
    /// - 失敗(`failed`): ✕ が優先。
    var centerSystemImage: String? = nil

    private var clamped: Double { min(max(progress, 0), 1) }
    private var isComplete: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.border, lineWidth: lineWidth)

            if failed {
                Circle().fill(AppColor.muted.opacity(0.22))
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(AppColor.muted)
            } else if isComplete {
                Circle().fill(tint)
                if let centerSystemImage {
                    // 完了時は色を反転: 背景 tint / アイコン白。
                    Image(systemName: centerSystemImage)
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white)
                } else if showsCheckmarkWhenComplete {
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
                if let centerSystemImage {
                    Image(systemName: centerSystemImage)
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: clamped)
        .animation(.easeInOut(duration: 0.25), value: failed)
        .accessibilityValue(failed ? "上限に達しました" : "\(Int((clamped * 100).rounded()))パーセント")
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
