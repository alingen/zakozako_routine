import SwiftUI

/// Home上部の莉央の表情。コメントは共通のリアクション条件から選ぶ。
enum RioHomeMood: Equatable {
    /// 今日の約束にまだ手をつけていない(約束が0件の日も含む)。
    case notStarted
    /// いくつか達成した。
    case inProgress
    /// 今日の約束をぜんぶ達成した。
    case allDone
    /// 「やらないこと」に負けた。
    case defeated

    var portraitAssetName: String {
        switch self {
        case .notStarted: return "portrait_rio_mischievous_default"
        case .inProgress: return "portrait_rio_smile"
        case .allDone: return "portrait_rio_triumphant"
        case .defeated: return "portrait_rio_unimpressed"
        }
    }

}

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

    /// シートの interactions でこの値を touch_area にした行があれば、下の既定文より優先する。
    var commentTouchArea: String {
        switch self {
        case .routineCompleted: return "reaction_routine_completed"
        case .allRoutinesCompleted: return "reaction_all_completed"
        case .timerFinished: return "reaction_timer_finished"
        }
    }

    var fallbackGroup: String {
        switch self {
        case .routineCompleted: return "home_routine_completed"
        case .allRoutinesCompleted: return "home_all_completed"
        case .timerFinished: return "home_timer_finished"
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
