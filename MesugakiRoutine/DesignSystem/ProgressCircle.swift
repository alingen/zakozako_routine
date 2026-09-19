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
    /// 「失敗」状態。true のとき、進捗に関わらず薄い円 + 失敗アイコンを表示する。
    var failed: Bool = false
    /// 円の中に表示する SF Symbol。
    /// - 未完了: 枠の中にアイコンを `tint` 色で表示(背景は透明=白)。
    /// - 完了: 背景 `tint` / アイコン白 に反転。
    /// - 失敗(`failed`): 失敗アイコンが優先。
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

/// 12時位置から時計回りに、円の内側を扇形で満たす進捗表示。
///
/// 背景と達成部分の両方に同じアイコンを重ね、達成部分だけ白いアイコンで
/// マスクすることで、円グラフの境界に合わせてアイコンの色も切り替える。
struct RoutineProgressPie: View {
    let progress: Double
    var size: CGFloat = 30
    var tint: Color = AppColor.primary
    var centerSystemImage: String? = nil

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColor.primarySoft)

            ProgressPieSlice(progress: clamped)
                .fill(tint)

            if let centerSystemImage {
                Image(systemName: centerSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)

                Image(systemName: centerSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .mask {
                        ProgressPieSlice(progress: clamped)
                            .fill(.black)
                    }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: clamped)
        .accessibilityValue("\(Int((clamped * 100).rounded()))パーセント")
    }
}

/// `RoutineProgressPie` の進捗面。0なら空、1なら真円になる。
struct ProgressPieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }
        guard clamped < 1 else { return Path(ellipseIn: rect) }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            ProgressCircle(progress: 0)
            ProgressCircle(progress: 0.25)
            ProgressCircle(progress: 0.5)
            ProgressCircle(progress: 0.75)
            ProgressCircle(progress: 1)
        }
        HStack(spacing: 20) {
            RoutineProgressPie(progress: 0, size: 52, centerSystemImage: "book.closed.fill")
            RoutineProgressPie(progress: 1.0 / 3.0, size: 52, centerSystemImage: "book.closed.fill")
            RoutineProgressPie(progress: 2.0 / 3.0, size: 52, centerSystemImage: "book.closed.fill")
            RoutineProgressPie(progress: 1, size: 52, centerSystemImage: "book.closed.fill")
        }
    }
    .padding()
    .background(AppColor.background)
}
