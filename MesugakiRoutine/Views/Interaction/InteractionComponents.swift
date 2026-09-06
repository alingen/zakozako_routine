import SwiftUI

struct InteractionCharacterCard: View {
    var name = "莉央"

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColor.primarySoft)
                Image(systemName: "sparkles")
                    .font(.title.bold())
                    .foregroundStyle(AppColor.primary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("現在のコーチ")
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
                Text(name)
                    .font(.title3.bold())
                    .foregroundStyle(AppColor.text)
                Text("今日の会話とストーリー")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColor.border)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodayConversationCard: View {
    let title: String
    let detail: String
    let hasResumePosition: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 48, height: 48)
                    .background(AppColor.primarySoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppColor.text)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                        .multilineTextAlignment(.leading)
                    if hasResumePosition {
                        Label("続きから", systemImage: "bookmark.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColor.secondary)
                    }
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColor.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColor.border)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
    }
}

struct InteractionDestinationCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.bold())
                .foregroundStyle(AppColor.secondary)
                .frame(width: 44, height: 44)
                .background(AppColor.secondary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundStyle(AppColor.muted)
        }
        .padding(16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColor.border)
        }
        .contentShape(Rectangle())
    }
}
