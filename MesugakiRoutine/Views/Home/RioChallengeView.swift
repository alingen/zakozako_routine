import SwiftUI

/// 既存の煽りをまず見せ、1タップでお題へ。記録・通知・タイマーには接続しない。
struct RioChallengeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var challenge: RioChallenge?

    let taunt: String
    let onDismiss: () -> Void
    var catalog: RioChallengeCatalog = .bundled

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    RioSpeechRow {
                        VStack(alignment: .leading, spacing: 10) {
                            OnboardingRioBubble(text: taunt)

                            if challenge != nil {
                                OnboardingRioBubble(text: "じゃあこれやってきて〜")
                                    .transition(
                                        reduceMotion
                                            ? .opacity
                                            : .offset(y: 8).combined(with: .opacity)
                                    )
                                    .accessibilityLabel("莉央、じゃあこれやってきて〜")
                            }
                        }
                    }
                    // お題の表示前後で莉央の顔の位置が動かないよう、下の領域を確保する。
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 150, alignment: .top)

                    if let challenge {
                        challengeCard(challenge)
                            .transition(.opacity)
                    } else {
                        Color.clear
                            .frame(height: 280)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentShape(Rectangle())
            .onTapGesture {
                if challenge == nil { showChallenge() }
            }
            .accessibilityElement(children: challenge == nil ? .ignore : .contain)
            .accessibilityLabel(challenge == nil ? "莉央、\(taunt)" : "")
            .accessibilityHint(challenge == nil ? "タップして次のセリフを表示" : "")
            .accessibilityAddTraits(challenge == nil ? .isButton : [])
            .accessibilityIdentifier(challenge == nil ? "rioChallengeTaunt" : "rioChallengeContent")
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    private func challengeCard(_ challenge: RioChallenge) -> some View {
        VStack(spacing: 20) {
            Text("莉央からのお題")
                .font(.headline)
                .foregroundStyle(AppColor.text)
                .accessibilityAddTraits(.isHeader)

            Text(challenge.text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 84)
                .id(challenge.id)
                .transition(.opacity)
                .accessibilityIdentifier("rioChallengeText")

            VStack(spacing: 8) {
                Button(action: onDismiss) {
                    Text("これやる")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AppColor.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rioChallengeAccept")

                Button(action: showChallenge) {
                    Text("別のお題")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rioChallengeReroll")
            }
        }
        .padding(24)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func showChallenge() {
        guard let next = catalog.next(excluding: challenge?.id) else {
            // データ欠落時もユーザーを閉じ込めない。通常は39件から選ばれる。
            if challenge == nil { onDismiss() }
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            challenge = next
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        Color.black.opacity(0.48).ignoresSafeArea()
        RioChallengeView(taunt: "よわよわメンタル出てきたね♡", onDismiss: {})
    }
}
