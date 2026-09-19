import SwiftUI

/// 初回起動時に、莉央と最初の約束を決める5画面のオンボーディング。
struct OnboardingSetupView: View {
    @Bindable var stateStore: OnboardingStateStore
    let onConfirmPromise: () -> Void

    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case name
        case customHabit
        case customGoal
        case customCue
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    Group {
                        switch stateStore.setupStep {
                        case .introduction:
                            introductionPage
                        case .habitSelection:
                            habitSelectionPage
                        case .goalSetting:
                            goalSettingPage
                        case .cueSelection:
                            cueSelectionPage
                        case .confirmation:
                            confirmationPage
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)

                bottomActions
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: stateStore.setupStep)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if stateStore.setupStep != .introduction {
                    Button {
                        focusedField = nil
                        stateStore.retreatSetup()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppColor.text)
                            .frame(width: 44, height: 44)
                            .background(AppColor.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("前の画面へ戻る")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                Text("莉央と最初の約束")
                    .font(.headline)
                    .foregroundStyle(AppColor.text)

                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            HStack(spacing: 8) {
                ForEach(OnboardingSetupStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= stateStore.setupStep.rawValue
                              ? AppColor.primary
                              : AppColor.border)
                        .frame(width: step == stateStore.setupStep ? 30 : 9, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("5ステップ中\(stateStore.setupStep.rawValue + 1)ステップ目")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppColor.background.opacity(0.97))
    }

    private var introductionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle("小さな約束から、はじめよう")

            rioMessage("もしかして習慣化アプリ入れただけで満足してないよね〜？w")

            systemExplanation(
                "毎日の小さな約束を達成して、莉央との会話や物語を楽しむアプリです。\n\nまずはあなたの名前と呼び方をおしえてください"
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("あなたの名前")
                    .font(.subheadline.weight(.semibold))
                TextField("名前を入力", text: $stateStore.draft.userName)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = nil }
                    .onChange(of: stateStore.draft.userName) { _, value in
                        if value.count > 20 {
                            stateStore.draft.userName = String(value.prefix(20))
                        }
                    }
                    .onboardingTextField()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("莉央からの呼ばれ方")
                    .font(.subheadline.weight(.semibold))

                choiceFlow {
                    ForEach(onboardingHonorifics) { honorific in
                        OnboardingChoiceChip(
                            title: honorific.displayName,
                            isSelected: stateStore.draft.userHonorific == honorific
                        ) {
                            stateStore.draft.userHonorific = honorific
                        }
                    }
                }
            }
        }
    }

    private var habitSelectionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle("まずは何を続けてみますか？")
            rioMessage("まずは1つでいいよ\n\(stateStore.draft.userHonorific.displayName)のよわよわメンタルじゃ何個も続かないでしょ〜w")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(RoutinePreset.onboarding) { preset in
                    OnboardingHabitCard(
                        title: preset.title,
                        iconName: preset.iconName,
                        isSelected: stateStore.draft.selectedHabitID == preset.id
                    ) {
                        chooseHabit(preset)
                    }
                }

                OnboardingHabitCard(
                    title: "自分で決める",
                    iconName: "pencil",
                    isSelected: stateStore.draft.selectedHabitID == "custom"
                ) {
                    chooseCustomHabit()
                }
            }

            if stateStore.draft.selectedHabitID == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("続けたいこと")
                        .font(.subheadline.weight(.semibold))
                    TextField("例：筋トレする", text: customHabitBinding)
                        .focused($focusedField, equals: .customHabit)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .onboardingTextField()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            systemFootnote("約束はあとで追加・変更できます")
        }
    }

    private var goalSettingPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle("どのくらいやりますか？")
            rioMessage("張り切って入れたのに明日すぐサボってそ〜w")
            systemExplanation("最初は少なすぎるくらいの目標を入れましょう。\n継続することが大切です。")

            VStack(alignment: .leading, spacing: 10) {
                Text(stateStore.draft.habitTitle)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)

                ForEach(goalOptions) { option in
                    OnboardingSelectionRow(
                        title: option.label,
                        isSelected: stateStore.draft.selectedGoalID == option.id
                    ) {
                        stateStore.draft.selectedGoalID = option.id
                        stateStore.draft.goalText = option.label
                        stateStore.draft.routineTitle = option.routineTitle
                        focusedField = nil
                    }
                }

                OnboardingSelectionRow(
                    title: "自分で決める",
                    isSelected: stateStore.draft.selectedGoalID == "custom"
                ) {
                    if stateStore.draft.selectedGoalID != "custom" {
                        stateStore.draft.selectedGoalID = "custom"
                        stateStore.draft.goalText = ""
                        stateStore.draft.routineTitle = ""
                    }
                    focusedField = .customGoal
                }
            }

            if stateStore.draft.selectedGoalID == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("できたと判断できる、具体的な約束")
                        .font(.subheadline.weight(.semibold))
                    TextField("例：筋トレを5分する", text: customGoalBinding)
                        .focused($focusedField, equals: .customGoal)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .onboardingTextField()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var cueSelectionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle("いつやりますか？")
            rioMessage("適当に『〇〇する』だけ決めてもどうせやらないでしょ〜w")
            systemExplanation("いつもしている行動の後に組み込んでみましょう。")

            VStack(spacing: 10) {
                ForEach(cueOptions) { option in
                    OnboardingSelectionRow(
                        title: option.title,
                        isSelected: stateStore.draft.selectedCueID == option.id
                    ) {
                        stateStore.draft.selectedCueID = option.id
                        stateStore.draft.cueText = option.title
                        focusedField = nil
                    }
                }

                OnboardingSelectionRow(
                    title: "自分で決める",
                    isSelected: stateStore.draft.selectedCueID == "custom"
                ) {
                    if stateStore.draft.selectedCueID != "custom" {
                        stateStore.draft.selectedCueID = "custom"
                        stateStore.draft.cueText = ""
                    }
                    focusedField = .customCue
                }
            }

            if stateStore.draft.selectedCueID == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("いつ実行するか")
                        .font(.subheadline.weight(.semibold))
                    TextField("例：仕事から帰ったら", text: $stateStore.draft.cueText)
                        .focused($focusedField, equals: .customCue)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .onboardingTextField()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var confirmationPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            onboardingTitle("最初の約束")

            VStack(alignment: .leading, spacing: 10) {
                Label(cueLeadText, systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(AppColor.muted)

                HStack(spacing: 14) {
                    Image(systemName: stateStore.draft.habitIconName ?? "checklist")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(AppColor.primary, in: Circle())

                    Text(stateStore.draft.trimmedRoutineTitle)
                        .font(.title2.weight(.bold))
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

            rioMessage("じゃあできたら教えてね〜")

            systemExplanation("休んだ日があっても、達成済みの記録や物語の進行は消えません。")
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                focusedField = nil
                if stateStore.setupStep == .confirmation {
                    onConfirmPromise()
                } else {
                    stateStore.advanceSetup()
                }
            } label: {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.primary)
            .disabled(!stateStore.canContinue())

            if stateStore.setupStep == .confirmation {
                Button("内容を変更する") {
                    stateStore.goToSetupStep(.habitSelection)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.primary)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var primaryButtonTitle: String {
        switch stateStore.setupStep {
        case .introduction: return "はじめる"
        case .confirmation: return "この約束ではじめる"
        default: return "次へ"
        }
    }

    private var onboardingHonorifics: [UserHonorific] {
        [.oniisan, .ojisan, .oneesan]
    }

    private var goalOptions: [OnboardingGoalOption] {
        switch stateStore.draft.selectedHabitID {
        case "onboarding-read-book":
            return [
                .init(id: "page-1", label: "1ページ", routineTitle: "本を1ページ読む"),
                .init(id: "page-5", label: "5ページ", routineTitle: "本を5ページ読む"),
                .init(id: "page-10", label: "10ページ", routineTitle: "本を10ページ読む"),
            ]
        case "onboarding-study":
            return [
                .init(id: "problem-1", label: "1問", routineTitle: "問題を1問解く"),
                .init(id: "minutes-5", label: "5分", routineTitle: "5分勉強する"),
                .init(id: "minutes-10", label: "10分", routineTitle: "10分勉強する"),
            ]
        case "onboarding-exercise":
            return minuteOptions(verb: "運動する")
        case "onboarding-drink-water":
            return [
                .init(id: "glass-1", label: "コップ1杯", routineTitle: "コップ1杯の水を飲む"),
                .init(id: "glass-2", label: "コップ2杯", routineTitle: "コップ2杯の水を飲む"),
                .init(id: "milliliter-500", label: "500ml", routineTitle: "水を500ml飲む"),
            ]
        case "onboarding-tidy-up":
            return minuteOptions(verb: "片づける")
        default:
            return []
        }
    }

    private func minuteOptions(verb: String) -> [OnboardingGoalOption] {
        [1, 5, 10].map { minutes in
            OnboardingGoalOption(
                id: "minutes-\(minutes)",
                label: "\(minutes)分",
                routineTitle: "\(minutes)分\(verb)"
            )
        }
    }

    private var cueOptions: [OnboardingCueOption] {
        [
            .init(id: "after-waking", title: "起きた後"),
            .init(id: "after-breakfast", title: "朝ごはんの後"),
            .init(id: "after-lunch", title: "昼ごはんの後"),
            .init(id: "after-arriving-home", title: "帰ったらすぐ"),
            .init(id: "after-bath", title: "お風呂の後"),
            .init(id: "after-brushing", title: "歯磨きの後"),
            .init(id: "before-sleep", title: "寝る前"),
        ]
    }

    private var customHabitBinding: Binding<String> {
        Binding(
            get: { stateStore.draft.habitTitle },
            set: { value in
                stateStore.draft.habitTitle = String(value.prefix(28))
                stateStore.draft.selectedGoalID = nil
                stateStore.draft.goalText = ""
                stateStore.draft.routineTitle = ""
            }
        )
    }

    private var customGoalBinding: Binding<String> {
        Binding(
            get: { stateStore.draft.routineTitle },
            set: { value in
                let limited = String(value.prefix(28))
                stateStore.draft.routineTitle = limited
                stateStore.draft.goalText = limited
            }
        )
    }

    private var cueLeadText: String {
        let cue = stateStore.draft.trimmedCueText
        guard !cue.isEmpty else { return "" }
        if cue.hasSuffix("に") || cue.hasSuffix("すぐ") || cue.hasSuffix("たら") {
            return cue
        }
        return "\(cue)に"
    }

    private func chooseHabit(_ preset: RoutinePreset) {
        guard stateStore.draft.selectedHabitID != preset.id else { return }
        stateStore.draft.selectedHabitID = preset.id
        stateStore.draft.habitTitle = preset.title
        stateStore.draft.habitIconName = preset.iconName
        clearGoalAndCue()
        focusedField = nil
    }

    private func chooseCustomHabit() {
        guard stateStore.draft.selectedHabitID != "custom" else {
            focusedField = .customHabit
            return
        }
        stateStore.draft.selectedHabitID = "custom"
        stateStore.draft.habitTitle = ""
        stateStore.draft.habitIconName = "checklist"
        clearGoalAndCue()
        focusedField = .customHabit
    }

    private func clearGoalAndCue() {
        stateStore.draft.selectedGoalID = nil
        stateStore.draft.goalText = ""
        stateStore.draft.routineTitle = ""
        stateStore.draft.selectedCueID = nil
        stateStore.draft.cueText = ""
    }

    private func onboardingTitle(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.bold))
            .foregroundStyle(AppColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rioMessage(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image("rio_blocked_behavior_taunt")
                .resizable()
                .scaledToFill()
                .frame(width: 92, height: 92, alignment: .top)
                .clipped()
                .background(AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColor.primary.opacity(0.35), lineWidth: 1)
                }
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.primarySoft, in: RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(text)")
    }

    private func systemExplanation(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(AppColor.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppColor.border, lineWidth: 1)
            }
    }

    private func systemFootnote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(AppColor.muted)
    }

    @ViewBuilder
    private func choiceFlow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8, content: content)
            VStack(alignment: .leading, spacing: 8, content: content)
        }
    }
}

private struct OnboardingGoalOption: Identifiable {
    let id: String
    let label: String
    let routineTitle: String
}

private struct OnboardingCueOption: Identifiable {
    let id: String
    let title: String
}

private struct OnboardingChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : AppColor.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(isSelected ? AppColor.primary : AppColor.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(isSelected ? AppColor.primary : AppColor.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OnboardingHabitCard: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : AppColor.primary)
                    .frame(width: 54, height: 54)
                    .background(isSelected ? AppColor.primary : AppColor.primarySoft, in: Circle())

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .padding(10)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColor.primary : AppColor.border, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OnboardingSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppColor.primary : AppColor.muted)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(isSelected ? AppColor.primary : AppColor.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func onboardingTextField() -> some View {
        font(.body)
            .foregroundStyle(AppColor.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColor.border, lineWidth: 1)
            }
    }
}

#Preview {
    OnboardingSetupView(
        stateStore: OnboardingStateStore(
            defaults: UserDefaults(suiteName: "OnboardingSetupViewPreview")!
        ),
        onConfirmPromise: {}
    )
}
