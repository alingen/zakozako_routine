import SwiftUI

/// Home上部の莉央の状態。表情と、CMS(interactions)から選ぶ一言の touch_area を決める。
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

    /// シートの interactions でこの値を touch_area にした行があれば優先して使う。
    var commentTouchArea: String {
        switch self {
        case .notStarted: return "home_not_started"
        case .inProgress: return "home_in_progress"
        case .allDone: return "home_all_done"
        case .defeated: return "home_defeated"
        }
    }
}

/// 約束を達成した瞬間の莉央の反応。
enum RioReactionKind: Equatable {
    /// 約束を1つ、目標回数まで達成した。
    case routineCompleted
    /// 今日の約束をぜんぶ達成した。
    case allRoutinesCompleted

    var portraitAssetName: String {
        switch self {
        case .routineCompleted: return "portrait_rio_smile"
        case .allRoutinesCompleted: return "portrait_rio_triumphant"
        }
    }

    /// シートの interactions でこの値を touch_area にした行があれば、下の既定文より優先する。
    var commentTouchArea: String {
        switch self {
        case .routineCompleted: return "reaction_routine_completed"
        case .allRoutinesCompleted: return "reaction_all_completed"
        }
    }

    var fallbackMessages: [String] {
        switch self {
        case .routineCompleted:
            return [
                "へぇ〜、ちゃんとやったんだ？ざこのくせに♡",
                "はいはい、えらいえらい♡",
                "おにいさんにしてはやるじゃん♡",
            ]
        case .allRoutinesCompleted:
            return [
                "え、今日の約束ぜんぶ終わったの？…ふーん、やるじゃん♡",
                "ぜんぶできたんだ？今日だけはざこって言わないであげる♡",
                "今日のおにいさん、ちょっとだけかっこいいかもw",
            ]
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

/// Home最上部の「今日の莉央」。タップで次の一言に替わる。
struct RioHomeHeader: View {
    let mood: RioHomeMood
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                RioAvatar(assetName: mood.portraitAssetName, size: 64)

                OnboardingRioBubble(text: text)
                    .multilineTextAlignment(.leading)
                    .id(text)
                    .transition(.opacity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: text)
        .animation(.easeInOut(duration: 0.18), value: mood)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(text)")
        .accessibilityHint("タップすると莉央が話します")
        .accessibilityAddTraits(.isButton)
    }
}

/// 約束の達成時に下から出る莉央の一言。画面はふさがず、数秒で消える。
struct RioReactionToast: View {
    let reaction: RioReaction

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RioAvatar(assetName: reaction.kind.portraitAssetName, size: 48)

            Text(reaction.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .padding(.trailing, 6)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.border.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: AppColor.text.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(reaction.text)")
        .accessibilityHint("タップして閉じる")
        .accessibilityAddTraits(.isButton)
    }
}
