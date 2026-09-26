import SwiftUI

/// 既存の煽りをまず見せ、1タップでお題へ。記録・通知・タイマーには接続しない。
struct RioChallengeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 最初に選んでおくお題。表示前も見えない状態で置き、画面の高さを実物で確保する。
    @State private var challenge: RioChallenge?
    @State private var isRevealed = false

    let taunt: String
    let onDismiss: () -> Void
    var catalog: RioChallengeCatalog = .bundled

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                // 下に寄せて、セリフとお題を一続きに読ませる(ホームの莉央とも重ならない)。
                VStack(spacing: 12) {
                    RioSpeechRow {
                        VStack(alignment: .leading, spacing: 10) {
                            OnboardingRioBubble(text: taunt)

                            OnboardingRioBubble(text: "じゃあこれやってきて〜")
                                .opacity(isRevealed ? 1 : 0)
                                .offset(y: isRevealed || reduceMotion ? 0 : 8)
                                .accessibilityHidden(!isRevealed)
                                .accessibilityLabel("莉央、じゃあこれやってきて〜")
                        }
                    }

                    // お題の表示前後で莉央の顔の位置が動かないよう、カードは最初から見えない状態で置いておく。
                    if let challenge {
                        challengeCard(challenge)
                            .opacity(isRevealed ? 1 : 0)
                            .allowsHitTesting(isRevealed)
                            .accessibilityHidden(!isRevealed)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentShape(Rectangle())
            // お題が出たあとは、カードの外のタップで閉じられるようにする(「これやる」を強いない)。
            .onTapGesture {
                if isRevealed {
                    onDismiss()
                } else {
                    reveal()
                }
            }
            .accessibilityElement(children: isRevealed ? .contain : .ignore)
            .accessibilityLabel(isRevealed ? "" : "莉央、\(taunt)")
            .accessibilityHint(isRevealed ? "" : "タップして次のセリフを表示")
            .accessibilityAddTraits(isRevealed ? [] : .isButton)
            .accessibilityIdentifier(isRevealed ? "rioChallengeContent" : "rioChallengeTaunt")
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .onAppear {
            if challenge == nil { challenge = catalog.next() }
        }
    }

    private func challengeCard(_ challenge: RioChallenge) -> some View {
        VStack(spacing: 12) {
            Text("莉央からのお題")
                .font(.headline)
                .foregroundStyle(AppColor.text)
                .accessibilityAddTraits(.isHeader)

            Text(challenge.text)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 56)
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

                Button(action: showAnotherChallenge) {
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
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // カードの余白や文面のタップで、外側の「閉じる」が反応しないようにする。
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {}
    }

    private func reveal() {
        guard challenge != nil else {
            // データ欠落時もユーザーを閉じ込めない。通常は39件から選ばれる。
            onDismiss()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isRevealed = true
        }
    }

    private func showAnotherChallenge() {
        guard let next = catalog.next(excluding: challenge?.id) else { return }
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
