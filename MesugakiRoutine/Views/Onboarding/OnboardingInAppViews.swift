import SwiftUI

struct OnboardingStoryUnlockView: View {
    let didCompleteFirstPromise: Bool
    let hasUnlockedStory: Bool
    let onContinue: () -> Void
    let onReadLater: () -> Void

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.48 : 0)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppColor.accent.opacity(0.23))
                        .frame(width: 104, height: 104)
                        .scaleEffect(isVisible ? 1 : 0.55)

                    Image(systemName: hasUnlockedStory ? "book.pages.fill" : "sparkles")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(hasUnlockedStory ? AppColor.primary : AppColor.secondary)
                        .symbolEffect(.bounce, value: isVisible)
                }

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(
                    hasUnlockedStory
                        ? "第一話を読む"
                        : (didCompleteFirstPromise
                            ? "もう一度確認する"
                            : "明日の約束を確認する"),
                    action: onContinue
                )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary, in: Capsule())
                    .buttonStyle(.plain)

                if hasUnlockedStory || didCompleteFirstPromise {
                    Button("あとで読む", action: onReadLater)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 390)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 28)
            .scaleEffect(isVisible ? 1 : 0.94)
            .opacity(isVisible ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                isVisible = true
            }
        }
    }

    private var title: String {
        if hasUnlockedStory { return "新しいストーリーが解禁されました" }
        return didCompleteFirstPromise
            ? "第一話を確認できませんでした"
            : "莉央との物語はここから"
    }

    private var message: String {
        if hasUnlockedStory {
            return "莉央との最初の物語が読めるようになりました"
        }
        if didCompleteFirstPromise {
            return "第一話の解禁状態を確認できませんでした。もう一度お試しください。"
        }
        return "今日はまだ達成にしていません。あとで約束を実行すると、物語の進行にも反映されます。"
    }
}

struct OnboardingFirstStoryReadView: View {
    let onContinue: () -> Void

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.48 : 0)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColor.primary)
                    .accessibilityHidden(true)

                Text("第一話を読み終わりました")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)

                Button("明日の約束を確認する", action: onContinue)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary, in: Capsule())
                    .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 390)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 28)
            .scaleEffect(isVisible ? 1 : 0.94)
            .opacity(isVisible ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                isVisible = true
            }
        }
    }
}

struct OnboardingTomorrowView: View {
    let cueText: String
    let routineTitle: String
    let iconName: String?
    let initialReminderTime: Date
    let isSaving: Bool
    let onEnableNotification: (Date) -> Void
    let onSkipNotification: () -> Void

    @State private var reminderTime: Date

    init(
        cueText: String,
        routineTitle: String,
        iconName: String?,
        initialReminderTime: Date,
        isSaving: Bool,
        onEnableNotification: @escaping (Date) -> Void,
        onSkipNotification: @escaping () -> Void
    ) {
        self.cueText = cueText
        self.routineTitle = routineTitle
        self.iconName = iconName
        self.initialReminderTime = initialReminderTime
        self.isSaving = isSaving
        self.onEnableNotification = onEnableNotification
        self.onSkipNotification = onSkipNotification
        _reminderTime = State(initialValue: initialReminderTime)
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("明日の約束")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppColor.text)

                    promiseCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("この約束を思い出せるように、お知らせしますか？")
                            .font(.headline)
                            .foregroundStyle(AppColor.text)

                        DatePicker(
                            "約束を始める時刻",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)

                        Text("この時刻から\(AppSettingsStore.notificationDelayMinutes)分後、まだ達成していなければ莉央がお知らせします。")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppColor.border, lineWidth: 1)
                    }

                    VStack(spacing: 12) {
                        Button {
                            onEnableNotification(reminderTime)
                        } label: {
                            HStack {
                                if isSaving { ProgressView().tint(.white) }
                                Text("通知を設定する")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.primary)
                        .disabled(isSaving)

                        Button("今はしない", action: onSkipNotification)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.primary)
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.light)
    }

    private var promiseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(cueLeadText, systemImage: "clock")
                .font(.headline)
                .foregroundStyle(AppColor.muted)

            HStack(spacing: 14) {
                Image(systemName: iconName ?? "checklist")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(AppColor.primary, in: Circle())

                Text(routineTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(AppColor.primary.opacity(0.25), lineWidth: 1)
        }
    }

    private var cueLeadText: String {
        let cue = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cue.hasSuffix("に") || cue.hasSuffix("すぐ") || cue.hasSuffix("たら") {
            return cue
        }
        return "\(cue)に"
    }
}

/// 通知の選択後、設定画面の上に重ねる最後の莉央の一言。
struct OnboardingTomorrowRioMessageView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.26)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                ScrollView {
                    VStack(spacing: 22) {
                        RioSpeechRow {
                            OnboardingRioBubble(text: "さすがに2日くらいはできるよね〜？w")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("莉央、さすがに2日くらいはできるよね〜？w")

                        Button("次へ", action: onContinue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(AppColor.surface.opacity(0.95), in: Capsule())
                            .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onContinue)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2)) {
                isVisible = true
            }
        }
    }
}
