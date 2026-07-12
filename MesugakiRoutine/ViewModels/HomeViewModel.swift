import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    private(set) var morningRoutine: Routine?
    private(set) var nightRoutine: Routine?
    private(set) var blockedBehaviors: [BlockedBehavior] = []
    var newBlockedBehaviorTitle: String = ""

    /// ホーム画面上部に出す、キャラクターからの一言。
    private(set) var homeComment: String = ""
    /// キャラクターの一言を生成している間 true(入力中インジケーターの表示に使う)。
    private(set) var isLoadingHomeComment = false

    /// Siriショートカット経由の起動直後、数秒だけ音声コマンドを受け付けている間 true。
    private(set) var isListeningForVoiceCommand = false

    private var dependencies: AppDependencies?
    private let quickVoiceCommandListener = QuickVoiceCommandListener()

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        morningRoutine = dependencies.routineRepository.fetch(type: .morning).first
        nightRoutine = dependencies.routineRepository.fetch(type: .night).first
        blockedBehaviors = dependencies.blockedBehaviorRepository.fetchAll()
        rescheduleNotifications()
    }

    /// サボり通知を、現在のルーティン状態(今日完了済みかどうか)にあわせて再計算する。
    private func rescheduleNotifications() {
        guard let dependencies else { return }
        let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
        Task {
            await dependencies.notificationScheduler.reschedule(
                routines: routines,
                sessionRepository: dependencies.sessionRepository
            )
        }
    }

    func addBlockedBehavior() {
        guard let dependencies else { return }
        let trimmed = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dependencies.blockedBehaviorRepository.create(
            title: trimmed,
            description: "",
            triggerText: trimmed,
            counterMessage: ""
        )
        newBlockedBehaviorTitle = ""
        reload()
    }

    func toggleBlockedBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.setActive(behavior, isActive: !behavior.isActive)
        reload()
    }

    func deleteBlockedBehaviors(at offsets: IndexSet) {
        guard let dependencies else { return }
        for index in offsets {
            dependencies.blockedBehaviorRepository.delete(blockedBehaviors[index])
        }
        reload()
    }

    /// 検出ワード・代替行動・検出時間帯を更新する(詳細編集シート用)。
    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        triggerText: String,
        alternativeAction: String,
        useTimeWindow: Bool,
        startTime: Date,
        endTime: Date
    ) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            triggerText: triggerText,
            alternativeAction: alternativeAction,
            activeStartMinute: useTimeWindow ? BlockedBehavior.minutes(from: startTime) : nil,
            activeEndMinute: useTimeWindow ? BlockedBehavior.minutes(from: endTime) : nil
        )
        reload()
    }

    /// 「負けそう」ボタンから、特定の「やらないこと」に対するキャラクターの声かけを取得する。
    /// ルーティンセッション外からの呼び出しのため、RoutineEngineには一切触れずCharacterEngineだけを使う。
    func confrontTemptation(_ behavior: BlockedBehavior?) async -> String {
        guard let dependencies else { return "" }
        let response = await dependencies.characterEngine.respond(
            to: .blockedBehaviorDetected(
                behaviorTitle: behavior?.title ?? "",
                counterMessage: behavior?.counterMessage ?? "",
                alternativeAction: behavior?.alternativeAction ?? ""
            )
        )
        return response.text
    }

    /// Siriショートカット経由の起動時にだけ呼ばれる。数秒間だけ音声を聞き取り、
    /// 「朝」「夜」といったキーワードから該当ルーティンを判定して返す(一致しなければ nil)。
    func listenForRoutineVoiceCommand() async -> Routine? {
        isListeningForVoiceCommand = true
        let text = await quickVoiceCommandListener.listenOnce()
        isListeningForVoiceCommand = false
        guard let text else { return nil }
        return matchRoutine(for: text)
    }

    private func matchRoutine(for text: String) -> Routine? {
        if text.contains("朝") { return morningRoutine }
        if text.contains("夜") { return nightRoutine }
        return nil
    }

    /// 中断中(完了していない)のセッションがあれば、その現在のステップ名を返す。無ければ nil。
    /// ホーム画面で「〇〇まで進行中」の表示・開始/再開ボタンの出し分けに使う。
    func inProgressStepTitle(for routine: Routine?) -> String? {
        guard let dependencies, let routine else { return nil }
        guard let session = dependencies.sessionRepository.fetchActiveSession(routineId: routine.id) else { return nil }
        guard let stepId = session.currentStepId else { return nil }
        return routine.orderedSteps.first { $0.id == stepId }?.title
    }

    /// ホーム画面上部のキャラクターコメントを取得し直す。継続日数・朝ルーティンの未着手判定を元に生成する。
    func loadHomeComment() async {
        guard let dependencies else { return }
        isLoadingHomeComment = true
        let response = await dependencies.characterEngine.respond(
            to: .homeGreeting(
                streakDays: currentStreakDays(),
                isMorningRoutinePending: isMorningRoutinePending()
            )
        )
        homeComment = response.text
        isLoadingHomeComment = false
    }

    /// 今日を含めて何日連続でルーティンを完了しているか。記録が無ければ1(今日が初日)を返す。
    private func currentStreakDays(calendar: Calendar = .current, now: Date = .now) -> Int {
        guard let dependencies else { return 1 }
        let completedDays = Set(
            dependencies.sessionRepository.fetchAllSessions()
                .filter { $0.status == .completed }
                .compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )
        var streak = 1
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// 「もう朝ルーティンを始めていい時間帯なのに、今日はまだ始めていない」かどうか。
    private func isMorningRoutinePending(calendar: Calendar = .current, now: Date = .now) -> Bool {
        guard let dependencies, let morning = morningRoutine else { return false }
        guard calendar.component(.hour, from: now) >= 10 else { return false }
        let completedToday = dependencies.sessionRepository.fetchAllSessions().contains { session in
            session.routineId == morning.id
                && session.status == .completed
                && session.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        return !completedToday
    }
}
