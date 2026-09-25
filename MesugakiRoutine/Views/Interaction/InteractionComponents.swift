import SwiftUI

struct InteractionCharacterSpeechBubble: View {
    let text: String
    var speakerName: String? = nil

    @ViewBuilder
    var body: some View {
        if let speakerName {
            labeledBubble(name: speakerName)
        } else {
            legacyBubble
        }
    }

    private func labeledBubble(name: String) -> some View {
        Text(text)
            .font(.body.weight(.semibold))
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .minimumScaleFactor(0.86)
            .padding(.leading, 20)
            .padding(.trailing, 30)
            .padding(.top, 25)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColor.surface.opacity(0.91))
                    .shadow(color: AppColor.text.opacity(0.14), radius: 16, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(AppColor.primary, in: Capsule())
                    .padding(.leading, 20)
                    .offset(y: -14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)、\(text)")
    }

    private var legacyBubble: some View {
        Text(text)
            .font(.body.weight(.bold))
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.86)
            .padding(.horizontal, 22)
            .padding(.top, 50)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background {
                InteractionSpeechBubbleShape()
                    .fill(AppColor.surface.opacity(0.94))
                    .shadow(color: AppColor.text.opacity(0.18), radius: 14, y: 7)
            }
            .overlay {
                InteractionSpeechBubbleShape()
                    .stroke(.white.opacity(0.96), lineWidth: 1.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("莉央、\(text)")
    }
}

private struct InteractionSpeechBubbleShape: Shape {
    private let tailHeight: CGFloat = 32
    private let cornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY + tailHeight,
            width: rect.width,
            height: max(0, rect.height - tailHeight)
        )
        let tailCenterX = rect.minX + rect.width * 0.56
        let tailHalfWidth: CGFloat = 18

        var path = Path(roundedRect: bodyRect, cornerRadius: cornerRadius)
        path.move(to: CGPoint(x: tailCenterX - tailHalfWidth, y: bodyRect.minY + 1))
        path.addLine(to: CGPoint(x: tailCenterX, y: rect.minY))
        path.addLine(to: CGPoint(x: tailCenterX + tailHalfWidth, y: bodyRect.minY + 1))
        path.closeSubpath()
        return path
    }
}

struct TodayConversationCard: View {
    let title: String
    let isUnread: Bool
    let hasResumePosition: Bool
    let isAvailable: Bool
    var height: CGFloat = 130
    let action: () -> Void

    private var statusText: String {
        guard isAvailable else { return "今日はまだ会話がありません" }
        if isUnread { return "莉央から話があるようです" }
        return "今日の会話は読み終えました"
    }

    var body: some View {
        Button(action: action) {
            InteractionHomeFeatureCard(
                kind: .today,
                title: title,
                detail: statusText,
                badge: hasResumePosition ? "続きから" : (isUnread ? "1" : nil),
                height: height
            )
        }
        .buttonStyle(InteractionCardButtonStyle())
        .disabled(!isAvailable)
    }
}

/// 会話がない日もカード全体は薄くしない。操作不可・アクセシビリティ状態はdisabledで保つ。
private struct InteractionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum InteractionHomeCardKind {
    case today, story, memories, freeTalk

    var symbol: String {
        switch self {
        case .today: return "bubble.left.and.bubble.right"
        case .story: return "book"
        case .memories: return "photo.on.rectangle.angled"
        case .freeTalk: return "bubble.left"
        }
    }

    var tint: Color { self == .today ? AppColor.primary : AppColor.secondary }
}

/// 読了・未読の状態にかかわらず、交流の4つの入口を2列で配置する。
struct InteractionHomeCardGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            content
        }
        .accessibilityLabel("交流メニュー")
    }
}

/// 交流の入口カード。今日の会話・思い出はアイコンのみ、ストーリー・ふりーとーくは立ち絵を薄く敷く。
struct InteractionHomeFeatureCard: View {
    let kind: InteractionHomeCardKind
    let title: String
    let detail: String
    var badge: String? = nil
    var showsUnreadDot = false
    var height: CGFloat = 130

    private var isFreeTalk: Bool { kind == .freeTalk }
    private var foreground: Color { isFreeTalk ? .white : AppColor.text }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(.ultraThinMaterial)
                (isFreeTalk ? AppColor.text.opacity(0.82) : kind.tint.opacity(0.09))

                // 今日の会話・思い出はアイコンだけで見せる(立ち絵を重ねると文字と被るため)。
                if kind == .story || kind == .freeTalk {
                    Image("rio_interaction_home")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: height, alignment: .top)
                        .clipped()
                        .opacity(isFreeTalk ? 0.26 : 0.36)

                    LinearGradient(
                        colors: isFreeTalk
                            ? [.clear, AppColor.text.opacity(0.86)]
                            : [AppColor.secondary.opacity(0.08), AppColor.surface.opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: kind.symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isFreeTalk ? .white.opacity(0.85) : kind.tint)

                    Spacer(minLength: 0)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if isFreeTalk {
                        Text("開発中")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().stroke(.white.opacity(0.5)))
                    } else {
                        HStack(alignment: .bottom, spacing: 2) {
                            Text(detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(kind == .today ? AppColor.primary : AppColor.muted)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(kind.tint)
                        }
                    }
                }
                .padding(12)

                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 23, minHeight: 23)
                        .background(AppColor.primary, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(9)
                } else if showsUnreadDot {
                    Circle()
                        .fill(AppColor.primary)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: proxy.size.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(.white.opacity(isFreeTalk ? 0.55 : 0.86), lineWidth: 1)
            }
            .shadow(color: AppColor.text.opacity(0.14), radius: 13, y: 5)
        }
        .frame(height: height)
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isFreeTalk { return "\(title)、開発中" }
        return showsUnreadDot ? "\(title)、\(detail)、未読あり" : "\(title)、\(detail)"
    }
}

struct InteractionProgressMiniCard: View {
    let progress: InteractionStoryProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.chapterTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
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

            Text(progress.nextStoryText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.muted)
                .lineLimit(2)
        }
        .padding(12)
        .frame(width: 188)
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
