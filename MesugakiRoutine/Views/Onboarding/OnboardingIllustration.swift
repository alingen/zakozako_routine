import SwiftUI

/// 操作を要求せず、オンボーディングの説明を補う小さな概念図。
struct OnboardingIllustration: View {
    enum Kind {
        case promiseToStory
        case repeatOneHabit(title: String, iconName: String)
        case smallGoal
        case cueToHabit(habitTitle: String, iconName: String)
        case askRioForHelp
        case completedPromise(cueText: String, routineTitle: String, iconName: String)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var portraitSize: CGFloat = 50
    @ScaledMetric(relativeTo: .caption) private var checkSize: CGFloat = 28

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .promiseToStory:
                promiseToStory
            case let .repeatOneHabit(title, iconName):
                repeatOneHabit(title: title, iconName: iconName)
            case .smallGoal:
                smallGoal
            case let .cueToHabit(habitTitle, iconName):
                cueToHabit(habitTitle: habitTitle, iconName: iconName)
            case .askRioForHelp:
                askRioForHelp
            case let .completedPromise(cueText, routineTitle, iconName):
                completedPromise(cueText: cueText, routineTitle: routineTitle, iconName: iconName)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            AppColor.background,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isImage)
    }

    private var promiseToStory: some View {
        VStack(spacing: 4) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("今日の約束", systemImage: "book")
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                        Text("本を1ページ読む")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            completionCheck
                            Text("達成！")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 8) {
                        habitIcon("book")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日の約束")
                                .font(.caption2)
                                .foregroundStyle(AppColor.muted)
                            Text("本を1ページ読む")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 2) {
                            completionCheck
                            Text("達成！")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.primary)
                        }
                    }
                }
            }
            .padding(10)
            .miniOnboardingCard()

            flowArrow

            HStack(alignment: .center, spacing: 8) {
                Image("rio_blocked_behavior_taunt")
                    .resizable()
                    .scaledToFill()
                    .frame(width: portraitSize, height: portraitSize, alignment: .top)
                    .clipped()
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("えらいえらい♡")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        AppColor.primarySoft,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }

            flowArrow

            let contentLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            contentLayout {
                contentCard("今日の会話", iconName: "bubble.left.and.bubble.right")
                contentCard("ストーリー", iconName: "book.closed")
            }
        }
    }

    private func repeatOneHabit(title: String, iconName: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                habitIcon(iconName)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .miniOnboardingCard()

            flowArrow

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
                ),
                spacing: 10
            ) {
                ForEach(1...4, id: \.self) { day in
                    VStack(spacing: 5) {
                        Text("\(day)日目")
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        completionCheck
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 3)

            flowArrow

            Text("いつもの行動に")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(AppColor.primarySoft.opacity(0.65), in: Capsule())
        }
    }

    @ViewBuilder
    private var smallGoal: some View {
        if dynamicTypeSize.isAccessibilitySize {
            smallGoalVertical
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    goalComparisonCard(isSmall: false)
                        .fixedSize(horizontal: true, vertical: false)
                    comparisonArrow(isHorizontal: true)
                    goalComparisonCard(isSmall: true)
                        .fixedSize(horizontal: true, vertical: false)
                }
                smallGoalVertical
            }
        }
    }

    private var smallGoalVertical: some View {
        VStack(spacing: 8) {
            goalComparisonCard(isSmall: false)
            comparisonArrow(isHorizontal: false)
            goalComparisonCard(isSmall: true)
        }
    }

    private func goalComparisonCard(isSmall: Bool) -> some View {
        VStack(spacing: 6) {
            Group {
                if isSmall {
                    completionCheck
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.muted)
                }
            }
            .frame(height: iconSize)

            Text(isSmall ? "スクワット" : "筋トレ")
                .font(.caption.weight(.semibold))
            Text(isSmall ? "1回" : "30分")
                .font(.headline)
            Text(isSmall ? "これならできる" : "むりそう…")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSmall ? AppColor.primary : AppColor.muted)
        }
        .foregroundStyle(isSmall ? AppColor.text : AppColor.muted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity)
        .miniOnboardingCard()
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSmall ? AppColor.primary.opacity(0.4) : .clear, lineWidth: 1)
        }
    }

    private func comparisonArrow(isHorizontal: Bool) -> some View {
        VStack(spacing: 3) {
            Text("小さく")
                .font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: isHorizontal ? "arrow.right" : "arrow.down")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppColor.primary)
    }

    @ViewBuilder
    private func cueToHabit(habitTitle: String, iconName: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            cueToHabitVertical(habitTitle: habitTitle, iconName: iconName)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    cueHabitCard(title: "歯を磨く", iconName: "mouth")
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.primary)
                    cueHabitCard(title: habitTitle, iconName: iconName)
                        .fixedSize(horizontal: true, vertical: false)
                }
                cueToHabitVertical(habitTitle: habitTitle, iconName: iconName)
            }
        }
    }

    private func cueToHabitVertical(habitTitle: String, iconName: String) -> some View {
        VStack(spacing: 8) {
            cueHabitCard(title: "歯を磨く", iconName: "mouth")
            flowArrow
            cueHabitCard(title: habitTitle, iconName: iconName)
        }
    }

    private func cueHabitCard(title: String, iconName: String) -> some View {
        VStack(spacing: 8) {
            habitIcon(iconName)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .miniOnboardingCard()
    }

    /// 「負けそう…」から莉央へ報告できる流れを、実際の操作を要求せずに伝える図。
    private var askRioForHelp: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                habitIcon("ellipsis.bubble")

                VStack(alignment: .leading, spacing: 3) {
                    Text("我慢が難しいとき")
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                    Text("負けそう…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("報告")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColor.primarySoft, in: Capsule())
            }
            .padding(10)
            .miniOnboardingCard()

            flowArrow

            let responseLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            responseLayout {
                Image("rio_blocked_behavior_taunt")
                    .resizable()
                    .scaledToFill()
                    .frame(width: portraitSize, height: portraitSize, alignment: .top)
                    .clipped()
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("負けそうだから莉央ちゃんに\n助け求めにきたんだw")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        AppColor.primarySoft,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
        }
    }

    private func completedPromise(cueText: String, routineTitle: String, iconName: String) -> some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("最初の約束を確認しましょう")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.primary)

                Label(cueText, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    habitIcon(iconName)
                    Text(routineTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .miniOnboardingCard()
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColor.primary.opacity(0.4), lineWidth: 1)
            }

            let reportLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            reportLayout {
                Text("できたら莉央に報告")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.primary)
                Image("rio_blocked_behavior_taunt")
                    .resizable()
                    .scaledToFill()
                    .frame(width: portraitSize, height: portraitSize, alignment: .top)
                    .clipped()
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func habitIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.primary)
            .frame(width: iconSize, height: iconSize)
            .background(AppColor.primarySoft, in: Circle())
    }

    private var completionCheck: some View {
        Image(systemName: "checkmark")
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColor.surface)
            .frame(width: checkSize, height: checkSize)
            .background(AppColor.primary, in: Circle())
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppColor.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
    }

    private func contentCard(_ title: String, iconName: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .foregroundStyle(AppColor.primary)
            Text(title)
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .miniOnboardingCard()
    }

    private var accessibilityDescription: String {
        switch kind {
        case .promiseToStory:
            return "図解。約束を達成すると莉央が反応し、今日の会話やストーリーにつながります。"
        case let .repeatOneHabit(title, _):
            return "図解。\(title)という1つの習慣を、1日目、2日目、3日目、4日目と繰り返し、いつもの行動にしていきます。"
        case .smallGoal:
            return "図解。筋トレ30分は難しそうでも、スクワット1回ならできそう。目標を小さくして始めます。"
        case let .cueToHabit(habitTitle, _):
            return "図解。歯を磨くという、いつもの行動の後に、\(habitTitle)を続けます。"
        case .askRioForHelp:
            return "図解。我慢が難しいときは、負けそうと莉央に報告できます。莉央が反応します。"
        case let .completedPromise(cueText, routineTitle, _):
            return "図解。最初の約束。\(cueText)、\(routineTitle)。できたら莉央に報告します。"
        }
    }
}

private extension View {
    func miniOnboardingCard() -> some View {
        background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.border.opacity(0.65), lineWidth: 1)
        }
    }
}
