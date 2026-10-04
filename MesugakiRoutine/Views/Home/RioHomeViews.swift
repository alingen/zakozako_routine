import SwiftUI

/// 約束を達成した瞬間の莉央の反応。
enum RioReactionKind: Equatable {
    /// 約束を1つ、目標回数まで達成した。
    case routineCompleted
    /// 今日の約束をぜんぶ達成した。
    case allRoutinesCompleted
    /// タイマーを最後までやった(目標回数にはまだ届いていない)。
    case timerFinished

    var portraitAssetName: String {
        switch self {
        case .routineCompleted, .timerFinished: return "portrait_rio_smile"
        case .allRoutinesCompleted: return "portrait_rio_triumphant"
        }
    }

}

struct RioReaction: Identifiable, Equatable {
    let id = UUID()
    let kind: RioReactionKind
    let text: String
}

/// 立ち絵(全身)の顔まわりを丸く切り抜いて表示する。素材そのものは加工しない。
struct RioAvatar: View {
    let assetName: String
    var size: CGFloat = 64

    // portrait_rio_* は同じ構図の全身絵。顔が収まる範囲を画像比率で指定する。
    private let cropWidthRatio: CGFloat = 0.35
    private let faceCenterXRatio: CGFloat = 0.5
    private let cropTopRatio: CGFloat = 0.02
    private let imageAspectRatio: CGFloat = 1.5

    var body: some View {
        let imageWidth = size / cropWidthRatio
        let imageHeight = imageWidth * imageAspectRatio

        Image(assetName)
            .resizable()
            .frame(width: imageWidth, height: imageHeight)
            .offset(
                x: size / 2 - imageWidth * faceCenterXRatio,
                y: -imageHeight * cropTopRatio
            )
            .frame(width: size, height: size, alignment: .topLeading)
            .background(AppColor.primarySoft)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(AppColor.primary.opacity(0.35), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
