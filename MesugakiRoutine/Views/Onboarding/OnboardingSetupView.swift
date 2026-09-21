import SwiftUI

/// 初回起動時に、莉央と最初の約束を決める5画面のオンボーディング。
struct OnboardingSetupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var stateStore: OnboardingStateStore
    let onConfirmPromise: () -> Void

    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case name
        case customHabit
        case customGoal
        case customCue
    }

    private var showsRioIntroduction: Bool {
        guard stateStore.setupStep == .introduction else { return false }
        switch stateStore.introductionStage {
        case .firstMessage, .secondMessage, .characterExplanation:
            return true
        case .appIntroduction, .nameEntry:
            return false
        }
    }

    private var showsHabitSelectionIntroduction: Bool {
        guard stateStore.setupStep == .habitSelection else { return false }
        return stateStore.habitSelectionStage == .firstMessage
            || stateStore.habitSelectionStage == .secondMessage
            || stateStore.habitSelectionStage == .systemExplanation
    }

    private var delayedGuidanceStep: OnboardingSetupStep? {
        let step = stateStore.setupStep
        guard let stage = stateStore.delayedGuidanceStage(for: step),
              stage == .presented || stage == .explanation else { return nil }
        return step
    }

    private var isWaitingForDelayedGuidance: Bool {
        stateStore.delayedGuidanceStage(for: stateStore.setupStep) == .waitingToPresent
    }

    private var showsOnboardingOverlay: Bool {
        showsRioIntroduction || showsHabitSelectionIntroduction || delayedGuidanceStep != nil
    }

    private var blocksUnderlyingInteraction: Bool {
        showsOnboardingOverlay || isWaitingForDelayedGuidance
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
                    .opacity(showsOnboardingOverlay ? 0 : 1)
            }
            .blur(radius: showsOnboardingOverlay ? 3 : 0)
            .allowsHitTesting(!blocksUnderlyingInteraction)
            .accessibilityHidden(blocksUnderlyingInteraction)

            if isWaitingForDelayedGuidance {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(0.5)
                    .accessibilityHidden(true)
            }

            if showsRioIntroduction {
                OnboardingRioIntroductionView(
                    stage: stateStore.introductionStage,
                    onContinue: { stateStore.advanceSetup() },
                    onBack: { stateStore.retreatSetup() }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if showsHabitSelectionIntroduction {
                OnboardingHabitSelectionIntroductionView(
                    stage: stateStore.habitSelectionStage,
                    habitTitle: stateStore.draft.habitTitle,
                    habitIconName: stateStore.draft.habitIconName,
                    onContinue: { stateStore.advanceSetup() },
                    onBack: { stateStore.retreatSetup() }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if let step = delayedGuidanceStep {
                delayedGuidanceOverlay(for: step)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .ignoresSafeArea(.keyboard, edges: showsOnboardingOverlay ? .bottom : [])
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.22), value: stateStore.setupStep)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.22), value: stateStore.introductionStage)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.22), value: showsOnboardingOverlay)
        .onChange(of: showsHabitSelectionIntroduction) { wasShowing, isShowing in
            guard wasShowing,
                  !isShowing,
                  stateStore.setupStep == .habitSelection,
                  stateStore.draft.selectedHabitID == "custom",
                  !stateStore.draft.hasHabitSelection else { return }
            focusedField = .customHabit
        }
        .task(id: stateStore.setupStep.rawValue) {
            await presentDelayedGuidanceIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if stateStore.setupStep != .introduction
                    || stateStore.introductionStage == .nameEntry {
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

                Text(stateStore.setupStep == .introduction ? "はじめに" : "莉央と最初の約束")
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
        Group {
            if stateStore.introductionStage == .appIntroduction {
                VStack(spacing: 22) {
                    Text("小さな約束から、はじめよう")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.text)

                    Text("毎日の小さな約束を達成して、キャラクターとの会話や物語を楽しむアプリです。")
                        .font(.title3)
                        .foregroundStyle(AppColor.text)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .transition(.opacity)
            } else {
                VStack(spacing: 22) {
                    Text("あなたの名前を教えてください。")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

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
                        .accessibilityLabel("あなたの名前")
                        .accessibilityIdentifier("onboarding.name")
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center)
        .onChange(of: stateStore.introductionStage) { _, stage in
            if stage != .nameEntry {
                focusedField = nil
            }
        }
    }

    private var habitSelectionPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle("まずは何を続けてみますか？")

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

            rioMessage("じゃあできたら教えてね〜")

            OnboardingExplanationPanel(
                illustration: .completedPromise(
                    cueText: cueLeadText,
                    routineTitle: stateStore.draft.trimmedRoutineTitle,
                    iconName: stateStore.draft.habitIconName ?? "checklist"
                ),
                message: "休んだ日があっても、達成済みの記録や物語の進行は消えません。",
                scrollsContent: false
            )
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
            .accessibilityIdentifier("onboarding.continue")

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
        case .introduction:
            return stateStore.introductionStage == .appIntroduction ? "次へ" : "はじめる"
        case .confirmation: return "この約束ではじめる"
        default: return "次へ"
        }
    }

    private var goalOptions: [OnboardingGoalOption] {
        switch stateStore.draft.selectedHabitID {
        case "onboarding-strength-training":
            return durationOptions { minutes in
                "筋トレを\(minutes)分する"
            }
        case "onboarding-walk":
            return durationOptions { minutes in
                "\(minutes)分散歩をする"
            }
        case "onboarding-study":
            return [
                .init(id: "problem-1", label: "1問", routineTitle: "問題を1問解く"),
                .init(id: "minutes-5", label: "5分", routineTitle: "5分勉強する"),
                .init(id: "minutes-10", label: "10分", routineTitle: "10分勉強する"),
            ]
        case "onboarding-journal":
            return [1, 3, 5].map { lines in
                OnboardingGoalOption(
                    id: "lines-\(lines)",
                    label: "\(lines)行",
                    routineTitle: "日記を\(lines)行書く"
                )
            }
        case "onboarding-read-book":
            return [
                .init(id: "page-1", label: "1ページ", routineTitle: "本を1ページ読む"),
                .init(id: "page-5", label: "5ページ", routineTitle: "本を5ページ読む"),
                .init(id: "page-10", label: "10ページ", routineTitle: "本を10ページ読む"),
            ]
        case "onboarding-tidy-up":
            return durationOptions { minutes in
                "\(minutes)分部屋を片付ける"
            }
        default:
            return []
        }
    }

    private func durationOptions(
        routineTitle: (Int) -> String
    ) -> [OnboardingGoalOption] {
        [1, 5, 10].map { minutes in
            OnboardingGoalOption(
                id: "minutes-\(minutes)",
                label: "\(minutes)分",
                routineTitle: routineTitle(minutes)
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

    private var selectedPromiseTitle: String {
        let routineTitle = stateStore.draft.trimmedRoutineTitle
        if !routineTitle.isEmpty {
            return routineTitle
        }
        return stateStore.draft.habitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentDelayedGuidanceIfNeeded() async {
        let step = stateStore.setupStep
        guard stateStore.delayedGuidanceStage(for: step) == .waitingToPresent else { return }

        do {
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            return
        }

        guard !Task.isCancelled,
              stateStore.setupStep == step,
              stateStore.delayedGuidanceStage(for: step) == .waitingToPresent else { return }
        stateStore.presentDelayedGuidanceIfNeeded(for: step)
    }

    @ViewBuilder
    private func delayedGuidanceOverlay(for step: OnboardingSetupStep) -> some View {
        switch step {
        case .goalSetting:
            OnboardingDelayedGuidanceView(
                stage: stateStore.delayedGuidanceStage(for: step) ?? .presented,
                message: "張り切って入れたのに明日すぐサボってそ〜w",
                illustration: .smallGoal,
                title: "最初は少なすぎるくらいでOK",
                explanation: "まずは、余裕でできる量から始めましょう。",
                onContinue: { stateStore.advanceDelayedGuidance(for: step) },
                onBack: { stateStore.retreatDelayedGuidance(for: step) }
            )
        case .cueSelection:
            OnboardingDelayedGuidanceView(
                stage: stateStore.delayedGuidanceStage(for: step) ?? .presented,
                message: "適当に『\(selectedPromiseTitle)』だけ決めてもどうせやらないでしょ〜w",
                illustration: .cueToHabit(
                    habitTitle: selectedPromiseTitle,
                    iconName: stateStore.draft.habitIconName ?? "checklist"
                ),
                title: "いつもの行動をきっかけに",
                explanation: "すでに毎日している行動のあとに、\n新しい約束をつなげてみましょう。",
                onContinue: { stateStore.advanceDelayedGuidance(for: step) },
                onBack: { stateStore.retreatDelayedGuidance(for: step) }
            )
        case .introduction, .habitSelection, .confirmation:
            EmptyView()
        }
    }

    private func chooseHabit(_ preset: RoutinePreset) {
        guard stateStore.draft.selectedHabitID != preset.id else {
            stateStore.beginHabitSelectionIntroductionIfNeeded()
            return
        }
        stateStore.draft.selectedHabitID = preset.id
        stateStore.draft.habitTitle = preset.title
        stateStore.draft.habitIconName = preset.iconName
        clearGoalAndCue()
        focusedField = nil
        stateStore.beginHabitSelectionIntroductionIfNeeded()
    }

    private func chooseCustomHabit() {
        guard stateStore.draft.selectedHabitID != "custom" else {
            if stateStore.habitSelectionStage == .completed {
                focusedField = .customHabit
            } else {
                focusedField = nil
                stateStore.beginHabitSelectionIntroductionIfNeeded()
            }
            return
        }
        stateStore.draft.selectedHabitID = "custom"
        stateStore.draft.habitTitle = ""
        stateStore.draft.habitIconName = "checklist"
        clearGoalAndCue()
        if stateStore.habitSelectionStage == .completed {
            focusedField = .customHabit
        } else {
            focusedField = nil
            stateStore.beginHabitSelectionIntroductionIfNeeded()
        }
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
            OnboardingRioPortrait()
            OnboardingRioBubble(text: text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(text)")
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

/// 1枚目の上に重ねる初対面の会話。画像は上端固定、セリフだけ下に追加する。
private struct OnboardingRioIntroductionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedContent: IntroductionContent?

    private enum IntroductionContent: Hashable {
        case firstMessage, secondMessage, explanation
    }

    let stage: OnboardingIntroductionStage
    let onContinue: () -> Void
    let onBack: () -> Void

    private var showsSecondMessage: Bool {
        stage == .secondMessage || stage == .characterExplanation
    }

    private var showsExplanation: Bool { stage == .characterExplanation }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 10).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.26)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onContinue)
                    .accessibilityHidden(true)

                VStack(spacing: OnboardingExplanationLayout.spacing(in: proxy.size)) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppColor.text)
                                .frame(width: 44, height: 44)
                                .background(AppColor.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("前の説明へ戻る")
                        Spacer()
                    }

                    VStack(spacing: OnboardingExplanationLayout.conversationToPanelSpacing(in: proxy.size)) {
                        HStack(alignment: .top, spacing: 10) {
                            OnboardingRioPortrait()

                            ScrollViewReader { scrollProxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        OnboardingRioBubble(text: "お、ざこのおにいさん発見〜")
                                            .accessibilityLabel("莉央、お、ざこのおにいさん発見〜")
                                            .accessibilityFocused($focusedContent, equals: .firstMessage)

                                        if showsSecondMessage {
                                            OnboardingRioBubble(text: "もしかして習慣化アプリ入れただけで満足してないよね？")
                                                .accessibilityLabel("莉央、もしかして習慣化アプリ入れただけで満足してないよね？")
                                                .accessibilityFocused($focusedContent, equals: .secondMessage)
                                                .id(IntroductionContent.secondMessage)
                                                .transition(revealTransition)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .scrollBounceBehavior(.basedOnSize)
                                .task(id: showsSecondMessage) {
                                    guard showsSecondMessage else { return }
                                    await Task.yield()
                                    guard !Task.isCancelled else { return }
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                        scrollProxy.scrollTo(IntroductionContent.secondMessage, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .frame(
                            height: OnboardingExplanationLayout.conversationHeight(
                                in: proxy.size,
                                typeSize: dynamicTypeSize,
                                hasMultipleMessages: true
                            ),
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onContinue)

                        // 会話の直下を基準にし、カードの上端を一定間隔で配置する。
                        ZStack(alignment: .top) {
                            Color.clear
                            if showsExplanation {
                                explanationPanel
                                    .transition(revealTransition)
                            }
                        }
                        .frame(height: OnboardingExplanationLayout.panelHeight(in: proxy.size, typeSize: dynamicTypeSize))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onContinue)

                        Button(action: onContinue) {
                            Text("次へ")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppColor.text)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 44)
                                .background(AppColor.surface.opacity(0.95), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .opacity(showsExplanation ? 1 : 0)
                        .allowsHitTesting(showsExplanation)
                        .accessibilityHidden(!showsExplanation)
                        .accessibilityIdentifier("onboarding.introduction.continue")
                    }
                    .padding(.top, OnboardingExplanationLayout.conversationTopPadding(in: proxy.size))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.22), value: stage)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onBack)
        .task(id: stage) {
            // 追加内容の表示が終わってからVoiceOverの読み上げ対象を移す。
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 250))
            guard !Task.isCancelled else { return }
            switch stage {
            case .appIntroduction, .nameEntry: focusedContent = nil
            case .firstMessage: focusedContent = .firstMessage
            case .secondMessage: focusedContent = .secondMessage
            case .characterExplanation: focusedContent = .explanation
            }
        }
    }

    private var explanationPanel: some View {
        OnboardingExplanationPanel(
            illustration: .promiseToStory,
            title: "約束を達成しよう",
            message: "毎日の約束を達成すると、\n莉央との会話や物語が進みます。"
        )
        .accessibilityFocused($focusedContent, equals: .explanation)
        .accessibilityIdentifier("onboarding.introduction.explanation")
    }
}

/// 2枚目で項目を選んだ直後に重ねる、莉央の助言と習慣についての説明。
private struct OnboardingHabitSelectionIntroductionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedContent: FocusedContent?

    private enum FocusedContent: Hashable {
        case firstMessage, secondMessage, explanation
    }

    let stage: OnboardingHabitSelectionStage
    let habitTitle: String
    let habitIconName: String?
    let onContinue: () -> Void
    let onBack: () -> Void

    private var showsExplanation: Bool {
        stage == .systemExplanation
    }

    private var showsSecondMessage: Bool {
        stage == .secondMessage || stage == .systemExplanation
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 10).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.26)
                    .ignoresSafeArea()
                    .onTapGesture(perform: continueFromMessageIfNeeded)
                    .accessibilityHidden(true)

                VStack(spacing: OnboardingExplanationLayout.spacing(in: proxy.size)) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppColor.text)
                                .frame(width: 44, height: 44)
                                .background(AppColor.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("前の説明へ戻る")
                        Spacer()
                    }

                    VStack(spacing: OnboardingExplanationLayout.conversationToPanelSpacing(in: proxy.size)) {
                        HStack(alignment: .top, spacing: 10) {
                            OnboardingRioPortrait()

                            ScrollViewReader { scrollProxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        OnboardingRioBubble(text: "まずは１つだけでいいよ〜")
                                            .accessibilityLabel("莉央、まずは１つだけでいいよ〜")
                                            .accessibilityFocused($focusedContent, equals: .firstMessage)

                                        if showsSecondMessage {
                                            OnboardingRioBubble(text: "おにいさんのよわよわメンタルじゃ何個も続かないでしょw")
                                                .accessibilityLabel("莉央、おにいさんのよわよわメンタルじゃ何個も続かないでしょw")
                                                .accessibilityFocused($focusedContent, equals: .secondMessage)
                                                .id(FocusedContent.secondMessage)
                                                .transition(revealTransition)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .scrollBounceBehavior(.basedOnSize)
                                .task(id: showsSecondMessage) {
                                    guard showsSecondMessage else { return }
                                    await Task.yield()
                                    guard !Task.isCancelled else { return }
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                        scrollProxy.scrollTo(FocusedContent.secondMessage, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .frame(
                            height: OnboardingExplanationLayout.conversationHeight(
                                in: proxy.size,
                                typeSize: dynamicTypeSize,
                                hasMultipleMessages: true
                            ),
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(perform: continueFromMessageIfNeeded)

                        ZStack(alignment: .top) {
                            Color.clear
                            if showsExplanation {
                                explanationPanel
                                    .transition(revealTransition)
                            }
                        }
                        .frame(height: OnboardingExplanationLayout.panelHeight(in: proxy.size, typeSize: dynamicTypeSize))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: continueFromMessageIfNeeded)

                        Button("次へ", action: onContinue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(AppColor.surface.opacity(0.95), in: Capsule())
                            .buttonStyle(.plain)
                            .opacity(showsExplanation ? 1 : 0)
                            .allowsHitTesting(showsExplanation)
                            .accessibilityHidden(!showsExplanation)
                            .accessibilityIdentifier("onboarding.habitIntroduction.continue")
                    }
                    .padding(.top, OnboardingExplanationLayout.conversationTopPadding(in: proxy.size))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.22), value: stage)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onBack)
        .task(id: stage) {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 250))
            guard !Task.isCancelled else { return }
            switch stage {
            case .awaitingSelection, .completed:
                focusedContent = nil
            case .firstMessage:
                focusedContent = .firstMessage
            case .secondMessage:
                focusedContent = .secondMessage
            case .systemExplanation:
                focusedContent = .explanation
            }
        }
    }

    private func continueFromMessageIfNeeded() {
        guard !showsExplanation else { return }
        onContinue()
    }

    private var explanationPanel: some View {
        OnboardingExplanationPanel(
            illustration: .repeatOneHabit(
                title: habitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "決めた習慣を1つ" : habitTitle,
                iconName: habitIconName ?? "checklist"
            ),
            title: "まずは1つに集中",
            message: "同じ行動を繰り返すことで、\n少しずつ『いつもの行動』になっていきます。"
        )
        .accessibilityFocused($focusedContent, equals: .explanation)
        .accessibilityIdentifier("onboarding.habitIntroduction.explanation")
    }
}

/// 3・4枚目に入って0.7秒後、同じ画面上に重ねる1回限りの補足説明。
private struct OnboardingDelayedGuidanceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedContent: FocusedContent?

    private enum FocusedContent: Hashable {
        case message, explanation
    }

    let stage: OnboardingDelayedGuidanceStage
    let message: String
    let illustration: OnboardingIllustration.Kind
    let title: String
    let explanation: String
    let onContinue: () -> Void
    let onBack: () -> Void

    private var showsExplanation: Bool {
        stage == .explanation
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 10).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.26)
                    .ignoresSafeArea()
                    .onTapGesture(perform: continueFromMessageIfNeeded)
                    .accessibilityHidden(true)

                VStack(spacing: OnboardingExplanationLayout.spacing(in: proxy.size)) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppColor.text)
                                .frame(width: 44, height: 44)
                                .background(AppColor.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("前の説明へ戻る")
                        Spacer()
                    }

                    VStack(spacing: OnboardingExplanationLayout.conversationToPanelSpacing(in: proxy.size)) {
                        HStack(alignment: .top, spacing: 10) {
                            OnboardingRioPortrait()

                            ScrollView {
                                OnboardingRioBubble(text: message)
                                    .accessibilityLabel("莉央、\(message)")
                                    .accessibilityFocused($focusedContent, equals: .message)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .frame(
                            height: OnboardingExplanationLayout.conversationHeight(
                                in: proxy.size,
                                typeSize: dynamicTypeSize,
                                hasMultipleMessages: false
                            ),
                            alignment: .top
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(perform: continueFromMessageIfNeeded)

                        ZStack(alignment: .top) {
                            Color.clear
                            if showsExplanation {
                                OnboardingExplanationPanel(
                                    illustration: illustration,
                                    title: title,
                                    message: explanation
                                )
                                .accessibilityFocused($focusedContent, equals: .explanation)
                                .accessibilityIdentifier("onboarding.delayedGuidance.explanation")
                                .transition(revealTransition)
                            }
                        }
                        .frame(height: OnboardingExplanationLayout.panelHeight(in: proxy.size, typeSize: dynamicTypeSize))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: continueFromMessageIfNeeded)

                        Button("次へ", action: onContinue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(AppColor.surface.opacity(0.95), in: Capsule())
                            .buttonStyle(.plain)
                            .opacity(showsExplanation ? 1 : 0)
                            .allowsHitTesting(showsExplanation)
                            .accessibilityHidden(!showsExplanation)
                            .accessibilityIdentifier("onboarding.delayedGuidance.continue")
                    }
                    .padding(.top, OnboardingExplanationLayout.conversationTopPadding(in: proxy.size))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.22), value: stage)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onBack)
        .task(id: stage) {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 250))
            guard !Task.isCancelled else { return }
            switch stage {
            case .presented:
                focusedContent = .message
            case .explanation:
                focusedContent = .explanation
            case .waitingToPresent, .completed:
                focusedContent = nil
            }
        }
    }

    private func continueFromMessageIfNeeded() {
        guard !showsExplanation else { return }
        onContinue()
    }
}

/// 説明が現れる前から同じ高さを確保し、セリフや莉央の位置を動かさない。
private enum OnboardingExplanationLayout {
    static func spacing(in size: CGSize) -> CGFloat {
        size.height < 680 ? 12 : 20
    }

    static func conversationTopPadding(in size: CGSize) -> CGFloat {
        size.height < 680 ? 8 : min(48, size.height * 0.06)
    }

    static func conversationToPanelSpacing(in size: CGSize) -> CGFloat {
        size.height < 680 ? 8 : 12
    }

    static func conversationHeight(
        in size: CGSize,
        typeSize: DynamicTypeSize,
        hasMultipleMessages: Bool
    ) -> CGFloat {
        let desiredHeight: CGFloat
        if typeSize.isAccessibilitySize {
            desiredHeight = hasMultipleMessages ? 210 : 150
        } else {
            desiredHeight = hasMultipleMessages ? 148 : 104
        }

        let maximumHeight = size.height * (hasMultipleMessages ? 0.28 : 0.20)
        return max(92, min(desiredHeight, maximumHeight))
    }

    static func panelHeight(in size: CGSize, typeSize: DynamicTypeSize) -> CGFloat {
        min(typeSize.isAccessibilitySize ? 420 : 340, size.height * 0.52)
    }
}

/// 図解を先に見せ、短い本文を添えるオンボーディング共通の説明パネル。
private struct OnboardingExplanationPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let illustration: OnboardingIllustration.Kind
    let title: String?
    let message: String?
    let scrollsContent: Bool

    init(
        illustration: OnboardingIllustration.Kind,
        title: String? = nil,
        message: String? = nil,
        scrollsContent: Bool = true
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.scrollsContent = scrollsContent
    }

    var body: some View {
        Group {
            if scrollsContent {
                GeometryReader { proxy in
                    ScrollView {
                        panelContent
                            .frame(
                                minHeight: dynamicTypeSize.isAccessibilitySize
                                    ? nil
                                    : proxy.size.height,
                                alignment: .center
                            )
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                panelContent
            }
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(0.95, anchor: .top)
        .accessibilityElement(children: .combine)
    }

    private var panelContent: some View {
        VStack(alignment: .center, spacing: 14) {
            OnboardingIllustration(kind: illustration)

            if title != nil || message != nil {
                VStack(alignment: .center, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    }
                }
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

private struct OnboardingRioPortrait: View {
    var body: some View {
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
    }
}

private struct OnboardingRioBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.primarySoft, in: RoundedRectangle(cornerRadius: 18))
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
