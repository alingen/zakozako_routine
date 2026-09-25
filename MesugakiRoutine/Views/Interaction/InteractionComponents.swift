import SwiftUI

/// 交流画面の莉央のひとこと。ホームや煽りと同じピンクの吹き出しで、白い操作部品と見分ける。
/// 莉央本人が大きく映っているので、名札やアバターは付けない。
struct InteractionCharacterSpeechBubble: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let text: String
    /// 読み上げで誰の言葉かを伝えるための名前。
    var speakerName: String = "莉央"

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.leading)
            // 大きな文字サイズでは行数を制限せず、全文を読めるようにする。
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .minimumScaleFactor(0.86)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 立ち絵の上でも輪郭が分かるよう、薄い影だけ付ける。
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppColor.primarySoft)
                    .shadow(color: AppColor.text.opacity(0.12), radius: 12, y: 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(speakerName)、\(text)")
    }
}

/// 今日の会話の入口。状態は説明文ではなく、バッジとボタンの色で示す。
struct TodayConversationDockButton: View {
    let title: String
    let isUnread: Bool
    let hasResumePosition: Bool
    let isAvailable: Bool
    let action: () -> Void

    private var statusText: String {
        guard isAvailable else { return "今日はまだ会話がありません" }
        if hasResumePosition { return "続きから読めます" }
        if isUnread { return "莉央から話があるようです" }
        return "今日の会話は読み終えました"
    }

    var body: some View {
        Button(action: action) {
            InteractionDockItem(
                kind: .today,
                title: title,
                badge: hasResumePosition ? "続き" : (isUnread ? "1" : nil),
                isEnabled: isAvailable
            )
        }
        .buttonStyle(InteractionDockButtonStyle())
        .disabled(!isAvailable)
        .accessibilityValue(statusText)
    }
}

/// 押したときに少し縮むだけの控えめなスタイル。
struct InteractionDockButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum InteractionHomeCardKind {
    case today, story, memories

    var symbol: String {
        switch self {
        case .today: return "bubble.left.and.bubble.right"
        case .story: return "book"
        case .memories: return "photo.on.rectangle.angled"
        }
    }

    var tint: Color { self == .today ? AppColor.primary : AppColor.secondary }
}

/// 交流の入口を1本のバーに横並びで置く。主役の莉央を隠さないよう、高さは低く抑える。
struct InteractionDock<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColor.surface.opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.86), lineWidth: 1)
        }
        .shadow(color: AppColor.text.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("交流メニュー")
    }
}

/// バーの中の1項目。アイコンと短いラベルだけを見せ、未読などはアイコン右上に出す。
struct InteractionDockItem: View {
    let kind: InteractionHomeCardKind
    let title: String
    var badge: String? = nil
    var showsUnreadDot = false
    var isEnabled = true

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isEnabled ? kind.tint : AppColor.muted)
                .frame(width: 44, height: 30)
                .overlay(alignment: .topTrailing) {
                    indicator
                        .offset(x: 6, y: -4)
                }

            // 「スト/ーリー」のような不自然な折り返しを避け、大きな文字サイズでは1行のまま縮める。
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isEnabled ? AppColor.text : AppColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // 隣の項目のラベルとくっつかないよう、左右に余白を取る。
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsUnreadDot ? "\(title)、未読あり" : title)
    }

    @ViewBuilder
    private var indicator: some View {
        if let badge, isEnabled {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(AppColor.primary, in: Capsule())
                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                .fixedSize()
                .accessibilityHidden(true)
        } else if showsUnreadDot {
            Circle()
                .fill(AppColor.primary)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .accessibilityHidden(true)
        }
    }
}

struct InteractionProgressMiniCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let progress: InteractionStoryProgressPresentation

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.chapterTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(progress.completedCount) / \(progress.totalCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
            .foregroundStyle(AppColor.text)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.secondary.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [AppColor.primarySoft, AppColor.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * progress.progressFraction)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            // タップでストーリー一覧へ移れることを示す。
            HStack(alignment: .center, spacing: 4) {
                Text(progress.nextStoryText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColor.muted)
                    .lineLimit(isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        // 大きな文字サイズでは幅を広げて、章名と進み具合が切れないようにする。
        .frame(width: isAccessibilitySize ? 260 : 188)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.9))
        }
        .shadow(color: AppColor.text.opacity(0.12), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.chapterTitle)、\(progress.completedCount)話読了、全\(progress.totalCount)話。\(progress.nextStoryText)")
    }
}
