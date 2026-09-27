import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = HomeViewModel()
    @State private var news = ZakoNewsStore.shared
    @State private var selectedNewsPost: ZakoNewsPost?
    @State private var showsNewsFeed = false
    @State private var homeIsVisible = false
    @State private var homeIsScrolling = false
    @State private var editingRoutine: Routine?
    @State private var editingBlockedBehavior: BlockedBehavior?
    @State private var activeTimer: ActiveRoutineTimer?
    @State private var presentedTimer: ActiveRoutineTimer?
    @State private var pendingTimerCompletion: PendingTimerCompletion?
    @State private var timerDialogID: UUID?
    @State private var backgroundTimerCompletionFeedbackTrigger = 0
    @State private var isPresentingNewRoutine = false
    @State private var isPresentingNewBlockedBehavior = false
    @State private var isShowingBlockedBehaviorDeleteError = false
    @State private var nextStrugglingTauntIndex = 0
    @State private var nextDefeatedTauntIndex = 0
    @State private var rioReaction: RioReaction?
    /// P2「ちょこん」: 未達成カードの上から顔を出している莉央。
    @State private var cardPeek: RioCardPeekRequest?
    /// 約束カードの位置(グローバル座標)。
    @State private var routineRowFrames: [UUID: CGRect] = [:]
    /// 莉央の層の位置(グローバル座標)。カードの位置をこの層の座標に直すのに使う。
    @State private var rioLayerFrame: CGRect = .zero
    /// 値を変えると、層に出ている莉央が途中でも引っ込む。
    @State private var rioLayerDismissTrigger = 0
    /// 放置で見にきた莉央(上から/右から)。
    @State private var idlePeek: RioIdlePeekRequest?
    /// 今回ホームを開いてから、頼んでいない介入(P2・放置)をもう出したか。開くたび1回まで。
    @State private var unrequestedPeekShownThisOpen = false
    /// 値を変えると、放置の10秒を数え直す(約束の報告など、ボタンの操作があったとき)。
    @State private var idleResetToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var appDialog: AppDialogRequest?
    private let onboardingRoutineID: UUID?
    private let highlightsDeferredReport: Bool
    private let onboardingReportActionTrigger: Int
    private let onOnboardingRoutineCompleted: () -> Void
    private let onOnboardingReportTargetFrameChange: (CGRect?) -> Void

    init(
        appDialog: Binding<AppDialogRequest?> = .constant(nil),
        onboardingRoutineID: UUID? = nil,
        highlightsDeferredReport: Bool = false,
        onboardingReportActionTrigger: Int = 0,
        onOnboardingRoutineCompleted: @escaping () -> Void = {},
        onOnboardingReportTargetFrameChange: @escaping (CGRect?) -> Void = { _ in }
    ) {
        _appDialog = appDialog
        self.onboardingRoutineID = onboardingRoutineID
        self.highlightsDeferredReport = highlightsDeferredReport
        self.onboardingReportActionTrigger = onboardingReportActionTrigger
        self.onOnboardingRoutineCompleted = onOnboardingRoutineCompleted
        self.onOnboardingReportTargetFrameChange = onOnboardingReportTargetFrameChange
    }

    private var hiddenTimerWatcherID: UUID? {
        guard let activeTimer,
              scenePhase == .active,
              presentedTimer == nil,
              activeTimer.session.phase == .running else { return nil }
        return activeTimer.id
    }

    private var canRotateNews: Bool {
        homeIsVisible && scenePhase == .active && !homeIsScrolling
            && selectedNewsPost == nil && !showsNewsFeed && appDialog == nil
            && editingRoutine == nil && editingBlockedBehavior == nil
            && !isPresentingNewRoutine && !isPresentingNewBlockedBehavior
            && presentedTimer == nil && rioReaction == nil
            && onboardingRoutineID == nil
    }

    /// 莉央の層を出してよい状態か。シート・タイマー・編集・ダイアログ・オンボーディング中は出さない。
    private var canShowRioLayer: Bool {
        homeIsVisible && scenePhase == .active
            && selectedNewsPost == nil && !showsNewsFeed && appDialog == nil
            && editingRoutine == nil && editingBlockedBehavior == nil
            && !isPresentingNewRoutine && !isPresentingNewBlockedBehavior
            && presentedTimer == nil && onboardingRoutineID == nil
    }

    var body: some View {
        List {
            todayRoutinesSection
            todayPromiseSection
            zakoBulletinSection
        }
        // 端末の大きさで List の余白が16/20ptに変わらないよう、他の画面(.padding())と同じ16ptに固定する。
        .contentMargins(.horizontal, 16, for: .scrollContent)
        // スクロール中は速報を切り替えない。List 全体に DragGesture を付けるとスクロールやタップを奪うため、スクロールの状態を見る。
        .pausesWhileScrolling($homeIsScrolling)
        .sheet(item: $selectedNewsPost) { post in ZakoNewsDetailView(post: post) }
        .sheet(isPresented: $showsNewsFeed) { ZakoNewsFeedSheet() }
        .task(id: canRotateNews) {
            guard canRotateNews else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(ZakoNewsConfiguration.rotationSeconds)) }
                catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { news.rotate() }
            }
        }
        .task(id: homeIsVisible && scenePhase == .active) {
            guard homeIsVisible && scenePhase == .active else { return }
            while !Task.isCancelled {
                await news.refreshIfNeeded()
                do { try await Task.sleep(for: .seconds(ZakoNewsConfiguration.refreshSeconds)) }
                catch { return }
            }
        }
        .appScreenBackground()
        .onPreferenceChange(HomeRoutineRowFramesKey.self) { routineRowFrames = $0 }
        // 莉央専用の層。莉央と吹き出し以外は下の一覧にタップが届く。
        .overlay { rioLayer }
        .onChange(of: homeIsScrolling) { _, scrolling in
            // スクロールが始まったら、出ている莉央はすぐ引っ込む(操作を優先)。
            if scrolling { rioLayerDismissTrigger += 1 }
        }
        .onChange(of: canShowRioLayer) { _, canShow in
            if !canShow { rioLayerDismissTrigger += 1 }
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .navigationDestination(item: $editingBlockedBehavior) { behavior in
            blockedBehaviorEditor(for: behavior)
        }
        .onChange(of: editingRoutine) { _, new in
            if new == nil { viewModel.reload() }
        }
        .onChange(of: editingBlockedBehavior) { _, new in
            if new == nil { viewModel.reload() }
        }
        .sheet(isPresented: $isPresentingNewRoutine, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                RoutineEditView(routine: nil)
            }
        }
        .sheet(isPresented: $isPresentingNewBlockedBehavior, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                BlockedBehaviorCreateView(
                    onRequestScreenTimeAuthorization: {
                        try await viewModel.requestScreenTimeAuthorization()
                    },
                    onSave: { draft in
                        viewModel.addBlockedBehavior(draft)
                    }
                )
            }
        }
        .sheet(
            item: $presentedTimer,
            onDismiss: recordPendingTimerCompletion
        ) { timer in
            RoutineTimerView(
                routineTitle: timer.routineTitle,
                routineIconName: timer.routineIconName,
                targetMinutes: timer.targetMinutes,
                session: timer.session,
                onClose: { presentedTimer = nil },
                onStop: { stopTimer(timer) },
                onComplete: { completedAt in
                    completeTimer(timer, at: completedAt)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(AppColor.background)
        }
        .alert("削除できませんでした", isPresented: $isShowingBlockedBehaviorDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
        .alert(
            "記録できませんでした",
            isPresented: Binding(
                get: { viewModel.routineOperationErrorMessage != nil },
                set: { if !$0 { viewModel.clearRoutineOperationError() } }
            )
        ) {
            if pendingTimerCompletion != nil {
                Button("再試行") {
                    viewModel.clearRoutineOperationError()
                    Task { @MainActor in
                        await Task.yield()
                        recordPendingTimerCompletion()
                    }
                }
                Button("閉じる", role: .cancel) {
                    pendingTimerCompletion = nil
                    viewModel.clearRoutineOperationError()
                }
            } else {
                Button("OK") {
                    viewModel.clearRoutineOperationError()
                }
            }
        } message: {
            Text(viewModel.routineOperationErrorMessage ?? "不明なエラーです")
        }
        .alert(
            "操作を完了できませんでした",
            isPresented: Binding(
                get: { viewModel.blockedBehaviorOperationErrorMessage != nil },
                set: { if !$0 { viewModel.clearBlockedBehaviorOperationError() } }
            )
        ) {
            Button("OK") {
                viewModel.clearBlockedBehaviorOperationError()
            }
        } message: {
            Text(viewModel.blockedBehaviorOperationErrorMessage ?? "不明なエラーです")
        }
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            homeIsVisible = true
            viewModel.reload()
            siriLaunchCoordinator.pendingOpenTodayRoutines = false
            refreshActiveTimer(at: .now)
            unrequestedPeekShownThisOpen = false
            presentCardPeekIfNeeded()
        }
        .onDisappear { homeIsVisible = false }
        // 放置の判定: 何も触らない状態が10秒続いたら、莉央が見にくる。
        // スクロール・シート・莉央の登場・ボタンの操作があると、キーが変わって数え直す。
        .task(id: idleWatchKey) {
            guard canShowRioLayer, !homeIsScrolling, rioReaction == nil, cardPeek == nil, idlePeek == nil else { return }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch { return }
            presentIdlePeekIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, presentedTimer == nil {
                viewModel.reload()
                refreshActiveTimer(at: .now)
                unrequestedPeekShownThisOpen = false
                presentCardPeekIfNeeded()
            }
        }
        .task(id: hiddenTimerWatcherID) {
            await watchHiddenTimer()
        }
        .sensoryFeedback(.success, trigger: backgroundTimerCompletionFeedbackTrigger)
    }

    private func blockedBehaviorEditor(for behavior: BlockedBehavior) -> some View {
        BlockedBehaviorCreateView(
            behavior: behavior,
            onRequestScreenTimeAuthorization: {
                try await viewModel.requestScreenTimeAuthorization()
            },
            onSave: { draft in
                viewModel.updateBlockedBehavior(behavior, with: draft)
            },
            onRequestDelete: {
                presentBlockedBehaviorDeleteConfirmation(for: behavior)
            }
        )
    }

    private func watchHiddenTimer() async {
        guard let timer = activeTimer,
              presentedTimer == nil,
              timer.session.phase == .running else { return }

        while !Task.isCancelled,
              activeTimer?.id == timer.id,
              presentedTimer == nil,
              timer.session.phase == .running {
            if let completedAt = timer.session.refresh(now: .now)
                ?? timer.session.completedAt {
                completeTimer(timer, at: completedAt)
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    // MARK: - 0. 莉央の層

    /// 一覧の上に重ねる莉央。同時に出すのは1体だけで、達成の反応(P1)を「ちょこん」(P2)より優先する。
    private var rioLayer: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { rioLayerFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in rioLayerFrame = frame }

                if let rioReaction {
                    RioPopUpReaction(
                        reaction: rioReaction,
                        containerWidth: proxy.size.width,
                        dismissTrigger: rioLayerDismissTrigger,
                        onFinished: {
                            if self.rioReaction?.id == rioReaction.id { self.rioReaction = nil }
                        }
                    )
                    .id(rioReaction.id)
                } else if let cardPeek, let globalFrame = routineRowFrames[cardPeek.routineID] {
                    RioCardPeek(
                        request: cardPeek,
                        cardFrame: globalFrame.offsetBy(dx: -rioLayerFrame.minX, dy: -rioLayerFrame.minY),
                        dismissTrigger: rioLayerDismissTrigger,
                        onFinished: {
                            if self.cardPeek?.id == cardPeek.id { self.cardPeek = nil }
                        }
                    )
                    .id(cardPeek.id)
                } else if let idlePeek {
                    idlePeekView(idlePeek, containerWidth: proxy.size.width)
                }
            }
        }
    }

    @ViewBuilder
    private func idlePeekView(_ request: RioIdlePeekRequest, containerWidth: CGFloat) -> some View {
        let onFinished: (RioIdlePeekEnding) -> Void = { ending in
            RioUnrequestedPeekSchedule.record(ending)
            if idlePeek?.id == request.id { idlePeek = nil }
        }
        switch request.kind {
        case .above:
            RioIdleAbovePeek(
                request: request,
                containerWidth: containerWidth,
                dismissTrigger: rioLayerDismissTrigger,
                onFinished: onFinished
            )
            .id(request.id)
        case let .right(routineID):
            if let globalFrame = routineRowFrames[routineID] {
                RioIdleRightPeek(
                    request: request,
                    cardFrame: globalFrame.offsetBy(dx: -rioLayerFrame.minX, dy: -rioLayerFrame.minY),
                    containerWidth: containerWidth,
                    dismissTrigger: rioLayerDismissTrigger,
                    onFinished: onFinished
                )
                .id(request.id)
            }
        }
    }

    private var idleWatchKey: String {
        [
            "\(canShowRioLayer)", "\(homeIsScrolling)", "\(idleResetToken)",
            rioReaction?.id.uuidString ?? "-", cardPeek?.id.uuidString ?? "-", idlePeek?.id.uuidString ?? "-",
        ].joined(separator: "|")
    }

    /// 放置で見にくる。未達成の約束があれば上から、全部達成していれば達成済みカードの右から。
    private func presentIdlePeekIfNeeded() {
        guard canShowRioLayer, !homeIsScrolling, rioReaction == nil, cardPeek == nil, idlePeek == nil,
              !unrequestedPeekShownThisOpen,
              // 読み上げを聞いている時間と放置を見分けられないので、VoiceOver 中は来ない。
              !UIAccessibility.isVoiceOverRunning,
              RioUnrequestedPeekSchedule.canShow() else { return }

        let unfinished = viewModel.todayRoutines.filter { !viewModel.todayProgress(for: $0).isCompletedToday }
        let kind: RioIdlePeekRequest.Kind
        if let first = unfinished.first {
            kind = .above(unfinishedRoutineTitle: first.title)
        } else if let card = visibleCompletedRoutineID() {
            kind = .right(routineID: card)
        } else {
            // 約束が0件、または達成済みカードが画面に見えていないときは上から。
            kind = .above(unfinishedRoutineTitle: nil)
        }
        unrequestedPeekShownThisOpen = true
        RioUnrequestedPeekSchedule.markShown()
        withAnimation(nil) { idlePeek = RioIdlePeekRequest(kind: kind) }
        AccessibilityNotification.Announcement("莉央がのぞいています").post()
    }

    /// 画面内に全体が見えている達成済みカードのうち、いちばん上のもの。
    private func visibleCompletedRoutineID() -> UUID? {
        viewModel.todayRoutines
            .filter { viewModel.todayProgress(for: $0).isCompletedToday }
            .compactMap { routine in routineRowFrames[routine.id].map { (routine.id, $0) } }
            .filter { _, frame in
                frame.minY >= rioLayerFrame.minY + 60 && frame.maxY <= rioLayerFrame.maxY - 60
            }
            .min { $0.1.minY < $1.1.minY }?.0
    }

    /// P2「ちょこん」: ホームを開いた直後、画面内でいちばん上の未達成カードから顔を出す(1日1回)。
    private func presentCardPeekIfNeeded() {
        Task { @MainActor in
            // カードの位置が決まるのを待つ。
            try? await Task.sleep(for: .milliseconds(900))
            let day = AppDay.startOfDay(for: .now)
            guard canShowRioLayer, !homeIsScrolling, rioReaction == nil, cardPeek == nil, idlePeek == nil,
                  !RioCardPeekSchedule.hasShown(on: day) else { return }

            // 莉央が出る余白がカードの上にあり、下に隠れていないカードだけを候補にする。
            let target = viewModel.todayRoutines
                .filter { !viewModel.todayProgress(for: $0).isCompletedToday }
                .compactMap { routine in routineRowFrames[routine.id].map { (routine, $0) } }
                .filter { _, frame in
                    frame.minY - rioLayerFrame.minY >= RioCardPeek.heightAboveEdge + 4
                        && frame.minY <= rioLayerFrame.maxY - 160
                }
                .min { $0.1.minY < $1.1.minY }
            guard let (routine, _) = target,
                  let text = RioCopy.random(group: "home_peek_unfinished", routineTitle: routine.title) else { return }

            RioCardPeekSchedule.markShown(on: day)
            // P2 も頼んでいない介入なので、今回開いた分の枠を使う。
            unrequestedPeekShownThisOpen = true
            RioUnrequestedPeekSchedule.markShown()
            withAnimation(nil) {
                cardPeek = RioCardPeekRequest(routineID: routine.id, text: text)
            }
            AccessibilityNotification.Announcement("莉央、\(text)").post()
        }
    }

    /// 約束が今回のタップ(またはタイマー)で目標に届いたとき、莉央が反応する。
    /// タイマーを最後までやったときは、目標回数に届いていなくてもひとこと言う。
    private func presentRioReactionIfNeeded(
        for routine: Routine,
        wasCompleted: Bool,
        finishedTimer: Bool = false
    ) {
        guard !wasCompleted, routine.id != onboardingRoutineID else { return }
        let kind: RioReactionKind
        if viewModel.todayProgress(for: routine).isCompletedToday {
            let allDone = viewModel.todayTotalCount > 0
                && viewModel.todayCompletedCount == viewModel.todayTotalCount
            kind = allDone ? .allRoutinesCompleted : .routineCompleted
        } else if finishedTimer {
            kind = .timerFinished
        } else {
            return
        }
        let reaction = viewModel.makeRioReaction(kind)
        // 「ちょこん」や放置で顔を出していたら、達成の反応に切り替える(同時に出すのは1体)。
        cardPeek = nil
        idlePeek = nil
        rioReaction = reaction
        AccessibilityNotification.Announcement("莉央、\(reaction.text)").post()
    }

    private func dismissRioReaction() {
        rioReaction = nil
    }

    // MARK: - 1. 今日の約束

    private var todayRoutinesSection: some View {
        Section {
            // 空の日は追加の入口をそのまま置く。編集はカード本体のタップで行う。
            if viewModel.todayRoutines.isEmpty {
                AddRoutineTaskRow {
                    isPresentingNewRoutine = true
                }
                .routineListRowStyle()
            }

            ForEach(viewModel.todayRoutines) { routine in
                routineListRow(routine)
                    // 莉央の層が「ちょこん」で顔を出す位置を決めるため、カードの位置を知らせる。
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeRoutineRowFramesKey.self,
                                value: [routine.id: proxy.frame(in: .global)]
                            )
                        }
                    }
                    .routineListRowStyle()
            }
        } header: {
            HStack(spacing: 8) {
                homeSectionTitle("今日の約束")
                Spacer()
                Text("\(viewModel.todayCompletedCount) / \(viewModel.todayTotalCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.text)
                    .accessibilityLabel("\(viewModel.todayTotalCount)件中\(viewModel.todayCompletedCount)件達成")
                Button {
                    isPresentingNewRoutine = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.primary)
                // 44pt のタップ領域を確保しつつ、見た目の位置は右端に揃える。
                .padding(.vertical, -8)
                .padding(.trailing, -12)
                .accessibilityLabel("約束を追加")
            }
            .homeSectionHeaderStyle()
        }
    }

    /// セクション見出し。カードのタイトル(headline)より一段小さくして、カードを主役にする。
    private func homeSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppColor.text)
            .accessibilityAddTraits(.isHeader)
    }

    /// 約束1件。カード本体は編集、時計はタイマー、右端の丸は達成状態の変更に分離する。
    @ViewBuilder
    private func routineListRow(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)
        let activeTimerForRoutine = activeTimer.flatMap {
            $0.routine.id == routine.id ? $0 : nil
        }

        RoutineTaskRow(
            title: routine.title,
            iconName: routine.iconName,
            cueText: routine.cueText,
            streakText: streak >= 1
                ? "\(streak)\(routine.period.streakUnitLabel)連続！"
                : "今日から",
            hasStreak: streak >= 1,
            progressText: progress.showsCountBreakdown
                ? "\(progress.done) / \(progress.target)回"
                : nil,
            progressFraction: progress.fraction,
            progressCount: progress.done,
            progressTarget: progress.target,
            timerStatusText: activeTimerForRoutine.map { timerStatusText(for: $0.session) },
            timerTargetDurationMinutes: routine.targetDurationMinutes,
            isTimerActive: activeTimerForRoutine != nil,
            isCompleted: progress.isCompletedToday,
            isHighlighted: false,
            allowsEditing: routine.id != onboardingRoutineID || highlightsDeferredReport,
            highlightsDeferredReport: highlightsDeferredReport && routine.id == onboardingRoutineID,
            completionActionTrigger: routine.id == onboardingRoutineID
                ? onboardingReportActionTrigger
                : 0,
            reportsCompletionButtonFrame: routine.id == onboardingRoutineID
                && !highlightsDeferredReport,
            onEdit: { requestRoutineEdit(routine) },
            onStartTimer: { openTimer(for: routine) },
            onAdvance: {
                idleResetToken += 1
                let completesTarget = progress.done + 1 >= progress.target
                let didUpdate = updateRoutineCompletion(routine, completed: true)
                if didUpdate, completesTarget, routine.id == onboardingRoutineID {
                    onOnboardingRoutineCompleted()
                }
                if didUpdate {
                    presentRioReactionIfNeeded(for: routine, wasCompleted: progress.isCompletedToday)
                }
                return didUpdate
            },
            onUndoCompletion: {
                idleResetToken += 1
                if rioReaction != nil {
                    dismissRioReaction()
                }
                return updateRoutineCompletion(routine, completed: false)
            },
            onCompletionButtonFrameChange: { frame in
                guard routine.id == onboardingRoutineID else { return }
                onOnboardingReportTargetFrameChange(frame)
            }
        )
    }

    // MARK: - 2. やらないこと

    @ViewBuilder
    private var todayPromiseSection: some View {
        Section {
            if let behavior = viewModel.currentBehavior {
                promiseCard(behavior)
                    .routineListRowStyle()
            } else {
                AddBlockedBehaviorTaskRow {
                    isPresentingNewBlockedBehavior = true
                }
                .routineListRowStyle()
            }

            if !viewModel.masteredBehaviors.isEmpty {
                DisclosureGroup("卒業したこと(\(viewModel.masteredBehaviors.count))") {
                    ForEach(viewModel.masteredBehaviors, id: \.id) { behavior in
                        Text(behavior.title)
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteMasteredBehavior(viewModel.masteredBehaviors[index])
                        }
                    }
                }
                .appCardRow()
            }
        } header: {
            homeSectionTitle("やらないこと")
                .homeSectionHeaderStyle()
        }
    }

    /// 「やらないこと」カード。カード本体は編集、右端の丸は危機／失敗の選択肢を表示する。
    @ViewBuilder
    private func promiseCard(_ behavior: BlockedBehavior) -> some View {
        let usage = viewModel.promiseUsage(for: behavior)
        let hasScreenTimeIssue = behavior.trackingKind == .screenTime
            && viewModel.screenTimeMonitoringIssueMessage != nil

        BlockedBehaviorTaskRow(
            title: behavior.title,
            iconName: behavior.iconName,
            statusText: promiseStatusText(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            statusColor: promiseStatusColor(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            hasStreak: !hasScreenTimeIssue && !usage.failed && behavior.currentStreakDays >= 1,
            detailText: promiseDetailText(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            progressFraction: usage.fraction,
            isFailed: usage.failed,
            needsRepair: hasScreenTimeIssue,
            onEdit: {
                editingBlockedBehavior = behavior
            },
            onAction: {
                if hasScreenTimeIssue {
                    Task {
                        await viewModel.repairScreenTimeMonitoring(behavior)
                    }
                } else {
                    presentBlockedBehaviorActions(for: behavior)
                }
            }
        )
    }

    private func promiseStatusText(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> String {
        if hasScreenTimeIssue { return "スクリーンタイムを再設定してください" }
        if usage.failed { return "失敗" }
        if behavior.currentStreakDays >= 1 { return "\(behavior.currentStreakDays)日達成！" }
        return "今日から"
    }

    private func promiseStatusColor(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> Color {
        if hasScreenTimeIssue || usage.failed { return AppColor.error }
        return AppColor.muted
    }

    private func promiseDetailText(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> String? {
        if hasScreenTimeIssue { return "タップして許可を確認" }
        if usage.failed {
            return behavior.trackingKind == .screenTime
                ? "今日は時間上限を超えました"
                : "\(usage.periodLabel)は上限に達しました"
        }
        return behavior.trackingKind == .screenTime
            ? "今日は\(formattedScreenTimeLimit(behavior.screenTimeLimitMinutes))まで"
            : "\(usage.periodLabel)はあと\(usage.remaining)回"
    }

    private func formattedScreenTimeLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes)分" }
        if remainingMinutes == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainingMinutes)分"
    }

    private func presentBlockedBehaviorActions(for behavior: BlockedBehavior) {
        appDialog = AppDialogRequest(
            title: "「\(behavior.title)」",
            message: nil,
            actions: [
                AppDialogAction("負けそう…") {
                    guard viewModel.recordPromiseUrge(behavior) else { return .dismiss }
                    return .showTaunt(nextTaunt(for: .struggling))
                },
                // 次に確認画面があるので、ここでは塗らない。Error の塗りは確認画面の「負けました…」だけ。
                AppDialogAction("負けました", style: .caution) {
                    .replace(failureConfirmation(for: behavior))
                },
                AppDialogAction("閉じる", style: .cancel) {
                    .dismiss
                },
            ]
        )
    }

    private func presentBlockedBehaviorDeleteConfirmation(for behavior: BlockedBehavior) {
        appDialog = AppDialogRequest(
            title: "本当に削除しますか？",
            message: "「\(behavior.title)」を削除します。",
            actions: [
                AppDialogAction("いいえ") {
                    .dismiss
                },
                AppDialogAction("はい", style: .destructive) {
                    if viewModel.deleteBlockedBehavior(behavior) {
                        editingBlockedBehavior = nil
                    } else {
                        isShowingBlockedBehaviorDeleteError = true
                    }
                    return .dismiss
                },
            ]
        )
    }

    private func failureConfirmation(for behavior: BlockedBehavior) -> AppDialogRequest {
        AppDialogRequest(
            title: "本当に負けましたか？",
            message: "「\(behavior.title)」の失敗を記録します。",
            actions: [
                AppDialogAction("まだ耐える") {
                    .dismiss
                },
                AppDialogAction("負けました…", style: .destructive) {
                    guard viewModel.recordPromiseFailure(behavior) else {
                        return .dismiss
                    }
                    return .showTaunt(nextTaunt(for: .defeated))
                },
            ]
        )
    }

    private func nextTaunt(for kind: BlockedBehaviorTauntKind) -> BlockedBehaviorTauntRequest {
        let messages = kind.messages
        guard !messages.isEmpty else {
            return BlockedBehaviorTauntRequest(text: viewModel.prohibitionReactionText ?? "",
                                              offersChallenge: kind == .struggling)
        }
        let index: Int
        switch kind {
        case .struggling:
            index = nextStrugglingTauntIndex % messages.count
            nextStrugglingTauntIndex = (nextStrugglingTauntIndex + 1) % messages.count
        case .defeated:
            index = nextDefeatedTauntIndex % messages.count
            nextDefeatedTauntIndex = (nextDefeatedTauntIndex + 1) % messages.count
        }
        return BlockedBehaviorTauntRequest(
            text: viewModel.prohibitionReactionText ?? messages[index],
            offersChallenge: kind == .struggling
        )
    }

    // MARK: - 3. みんなのざこ速報

    private var zakoBulletinSection: some View {
        Section {
            // 約束・やらないことのカードと同じ幅・角丸に揃える。
            VStack(alignment: .leading, spacing: 8) {
                // ひとことの案内は、自分の投稿の行(「＋ ひとことを添える」)が受け持つ。
                ZakoBulletinFeedView(items: news.rotation.visible) { selectedNewsPost = $0 }
                if let message = news.errorMessage {
                    Text(message).font(.caption).foregroundStyle(AppColor.muted)
                    Button("再試行") { Task { await news.sendPending(); await news.refreshIfNeeded(force: true) } }
                        .font(.footnote).disabled(news.isLoading)
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 1)
                }
                .routineListRowStyle()
        } header: {
            HStack {
                homeSectionTitle("みんなのざこ速報")
                Spacer(minLength: 8)
                // 背景色の上なので本文色にし、44pt のタップ範囲を取りつつ見た目の位置は右端にそろえる。
                Button {
                    showsNewsFeed = true
                } label: {
                    HStack(spacing: 2) {
                        Text("すべて見る")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
                .accessibilityLabel("みんなのざこ速報をすべて見る")
            }.homeSectionHeaderStyle()
        }
    }

    private func updateRoutineCompletion(_ routine: Routine, completed: Bool) -> Bool {
        let didUpdate = completed
            ? viewModel.advanceRoutine(routine)
            : viewModel.setRoutineCompletion(routine, completed: false)
        if didUpdate,
           completed,
           let timer = activeTimer,
           timer.routine.id == routine.id {
            stopTimer(timer)
        }
        return didUpdate
    }

    private func recordPendingTimerCompletion() {
        guard let pendingTimerCompletion else { return }
        let routine = pendingTimerCompletion.routine
        let progress = viewModel.todayProgress(for: routine)
        let completesTarget = progress.done + 1 >= progress.target
        if viewModel.advanceRoutine(
            routine,
            now: pendingTimerCompletion.completedAt
        ) {
            self.pendingTimerCompletion = nil
            if completesTarget, routine.id == onboardingRoutineID {
                onOnboardingRoutineCompleted()
            }
            presentRioReactionIfNeeded(
                for: routine,
                wasCompleted: progress.isCompletedToday,
                finishedTimer: true
            )
        }
    }

    private func openTimer(for routine: Routine) {
        if let activeTimer {
            if let completedAt = activeTimer.session.refresh(now: .now)
                ?? activeTimer.session.completedAt {
                completeTimer(activeTimer, at: completedAt)
                return
            }

            if activeTimer.routine.id == routine.id {
                presentedTimer = activeTimer
            } else {
                presentTimerReplacementConfirmation(
                    runningTimer: activeTimer,
                    newRoutine: routine
                )
            }
            return
        }

        startTimer(for: routine)
    }

    private func startTimer(for routine: Routine) {
        let timer = ActiveRoutineTimer(routine: routine)
        activeTimer = timer
        presentedTimer = timer
    }

    private func requestRoutineEdit(_ routine: Routine) {
        guard let runningTimer = activeTimer,
              runningTimer.routine.id == routine.id else {
            editingRoutine = routine
            return
        }

        if let completedAt = runningTimer.session.refresh(now: .now)
            ?? runningTimer.session.completedAt {
            completeTimer(runningTimer, at: completedAt)
            return
        }

        let request = AppDialogRequest(
            title: "タイマーを停止しますか？",
            message: "「\(runningTimer.routineTitle)」を編集するには、動作中のタイマーを停止してください。",
            actions: [
                AppDialogAction("戻る") {
                    timerDialogID = nil
                    return .dismiss
                },
                AppDialogAction("停止して編集", style: .destructive) {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    stopTimer(runningTimer)
                    editingRoutine = routine
                    return .dismiss
                },
            ]
        )
        timerDialogID = request.id
        appDialog = request
    }

    private func presentTimerReplacementConfirmation(
        runningTimer: ActiveRoutineTimer,
        newRoutine: Routine
    ) {
        let request = AppDialogRequest(
            title: "別のタイマーが動作中です",
            message: "「\(runningTimer.routineTitle)」を停止して「\(newRoutine.title)」を開始しますか？",
            actions: [
                AppDialogAction("今のタイマーを見る") {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    presentedTimer = runningTimer
                    return .dismiss
                },
                AppDialogAction("切り替える", style: .destructive) {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    stopTimer(runningTimer)
                    startTimer(for: newRoutine)
                    return .dismiss
                },
            ]
        )
        timerDialogID = request.id
        appDialog = request
    }

    private func refreshActiveTimer(at date: Date) {
        guard let activeTimer else { return }
        if let completedAt = activeTimer.session.refresh(now: date)
            ?? activeTimer.session.completedAt {
            completeTimer(activeTimer, at: completedAt)
        }
    }

    private func completeTimer(_ timer: ActiveRoutineTimer, at completedAt: Date) {
        guard activeTimer?.id == timer.id else { return }
        activeTimer = nil
        if let timerDialogID, appDialog?.id == timerDialogID {
            appDialog = nil
        }
        timerDialogID = nil

        if presentedTimer?.id == timer.id {
            pendingTimerCompletion = PendingTimerCompletion(
                routine: timer.routine,
                completedAt: completedAt
            )
            presentedTimer = nil
        } else {
            backgroundTimerCompletionFeedbackTrigger += 1
            pendingTimerCompletion = PendingTimerCompletion(
                routine: timer.routine,
                completedAt: completedAt
            )
            recordPendingTimerCompletion()
        }
    }

    private func stopTimer(_ timer: ActiveRoutineTimer) {
        guard activeTimer?.id == timer.id else { return }
        timer.session.stop()
        activeTimer = nil
        if presentedTimer?.id == timer.id {
            presentedTimer = nil
        }
    }

    private func timerStatusText(for session: RoutineTimerSession) -> String {
        switch session.phase {
        case .running:
            "残り \(session.formattedRemainingDuration)"
        case .paused:
            "一時停止 \(session.formattedRemainingDuration)"
        case .completed:
            "目標達成"
        case .stopped:
            "停止中"
        }
    }
}

private final class ActiveRoutineTimer: Identifiable {
    let id = UUID()
    let routine: Routine
    let routineTitle: String
    let routineIconName: String?
    let targetMinutes: Int
    let session: RoutineTimerSession

    @MainActor
    init(routine: Routine, now: Date = .now) {
        self.routine = routine
        routineTitle = routine.title
        routineIconName = routine.iconName
        targetMinutes = max(routine.targetDurationMinutes ?? 1, 1)
        session = RoutineTimerSession(
            targetMinutes: targetMinutes,
            now: now
        )
    }
}

private struct PendingTimerCompletion {
    let routine: Routine
    let completedAt: Date
}

enum BlockedBehaviorTauntKind {
    case struggling
    case defeated

    var messages: [String] {
        switch self {
        case .struggling: return RioCopy.lines(group: "blocked_struggling")
        case .defeated: return RioCopy.lines(group: "blocked_defeated")
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(SiriLaunchCoordinator())
    .modelContainer(
        for: [
            Routine.self,
            BlockedBehavior.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ],
        inMemory: true
    )
}

private extension View {
    /// スクロール中かどうかを知らせる。iOS 17 では取得できないため、常に止まっている扱いにする。
    @ViewBuilder
    func pausesWhileScrolling(_ isScrolling: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, phase in
                isScrolling.wrappedValue = phase != .idle
            }
        } else {
            self
        }
    }
}
