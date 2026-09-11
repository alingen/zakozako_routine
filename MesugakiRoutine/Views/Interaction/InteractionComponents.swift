import SwiftUI

struct InteractionCharacterSpeechBubble: View {
    let text: String

    var body: some View {
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
    let action: () -> Void

    private var statusText: String {
        guard isAvailable else { return "今日はまだ会話がありません" }
        if isUnread { return "莉央から話があるようです" }
        return "今日の会話は読み終えました"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(AppColor.primary, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.muted)

                        if isUnread && isAvailable {
                            Text("NEW")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppColor.primary, in: Capsule())
                        } else if hasResumePosition {
                            Text("続きから")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.secondary)
                        }
                    }

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppColor.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.9))
            }
            .shadow(color: AppColor.text.opacity(0.12), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.68)
    }
}

struct InteractionHomeDestinationButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(AppColor.secondary, in: Circle())

            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(AppColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: 88, height: 78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.9))
        }
        .shadow(color: AppColor.text.opacity(0.16), radius: 10, y: 4)
        .contentShape(Rectangle())
    }
}
