import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    private(set) var morningRoutine: Routine?
    private(set) var nightRoutine: Routine?

    /// 現在挑戦中の「やらないこと」(あれば1件)。
    private(set) var currentBehavior: BlockedBehavior?
    /// 14日間守り切って卒業した「やらないこと」。新しい順。
    private(set) var masteredBehaviors: [BlockedBehavior] = []
    /// 前日分の「まもれた/まもれなかった」がまだ未記録なら、その確認対象。
    private(set) var pendingCheckInBehavior: BlockedBehavior?
    /// 解放済みで未完了のイベント(あれば「話したいことがあるみたい」を出す)。
    private(set) var presentableEvent: EventDefinition?
    /// キャラクター名(「〇〇が話したいことがあるみたい」の表示に使う)。
    private(set) var characterName = "小悪魔コーチ"
    var newBlockedBehaviorTitle: String = ""
    var newBlockedBehaviorReason: String = ""
    var newBlockedBehaviorAlternativeAction: String = ""

    /// ホーム画面上部に出す、キャラクターからの一言。
    private(set) var homeComment: String = ""
    /// キャラクターの一言を生成している間 true(入力中インジケーターの表示に使う)。
    private(set) var isLoadingHomeComment = false

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        characterName = dependencies?.characterEngine.activePreset.name ?? characterName
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        morningRoutine = dependencies.routineRepository.fetch(type: .morning).first
        nightRoutine = dependencies.routineRepository.fetch(type: .night).first
        currentBehavior = dependencies.blockedBehaviorRepository.fetchActive()
        masteredBehaviors = dependencies.blockedBehaviorRepository.fetchMastered()
        pendingCheckInBehavior = dependencies.blockedBehaviorRepository.pendingCheckIn()
        dependencies.eventUnlockService.refreshUnlocks()
        presentableEvent = dependencies.eventUnlockService.nextPresentableEvent()
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

    /// 現在挑戦中の項目が無い(未着手 or 卒業済み)場合のみ、新しい「やらないこと」を追加できる。
    var canAddBlockedBehavior: Bool {
        dependencies?.blockedBehaviorRepository.canAddNew() ?? false
    }

    func addBlockedBehavior() {
        guard let dependencies, canAddBlockedBehavior else { return }
        let title = newBlockedBehaviorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let reason = newBlockedBehaviorReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternativeAction = newBlockedBehaviorAlternativeAction.trimmingCharacters(in: .whitespacesAndNewlines)
        dependencies.blockedBehaviorRepository.create(
            title: title,
            reason: reason,
            alternativeAction: alternativeAction,
            triggerText: title,
            counterMessage: ""
        )
        newBlockedBehaviorTitle = ""
        newBlockedBehaviorReason = ""
        newBlockedBehaviorAlternativeAction = ""
        reload()
    }

    func deleteMasteredBehavior(_ behavior: BlockedBehavior) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.delete(behavior)
        reload()
    }

    /// 検出ワード・理由・検出時間帯を更新する(詳細編集シート用)。
    func updateBlockedBehaviorDetails(
        _ behavior: BlockedBehavior,
        reason: String,
        alternativeAction: String,
        triggerText: String,
        useTimeWindow: Bool,
        startTime: Date,
        endTime: Date
    ) {
        guard let dependencies else { return }
        dependencies.blockedBehaviorRepository.updateDetails(
            behavior,
            reason: reason,
            alternativeAction: alternativeAction,
            triggerText: triggerText,
            activeStartMinute: useTimeWindow ? BlockedBehavior.minutes(from: startTime) : nil,
            activeEndMinute: useTimeWindow ? BlockedBehavior.minutes(from: endTime) : nil
        )
        reload()
    }

    /// 前日分の「まもれた/まもれなかった」を記録する。
    /// 「まもれた」場合は信頼度を加算し(ルーティン完了と同じ +1)、累積回数を増やしてイベント解放を再評価する。
    func answerCheckIn(protected: Bool) {
        guard let dependencies, let behavior = pendingCheckInBehavior else { return }
        dependencies.blockedBehaviorRepository.recordCheckIn(behavior, protected: protected)
        if protected {
            dependencies.trustRepository.increment(by: 1)
            AppSettingsStore.blockedBehaviorProtectedCount += 1
            dependencies.eventUnlockService.refreshUnlocks()
        }
        reload()
    }

    /// 「負けそう」ボタンから、現在挑戦中の「やらないこと」に対するキャラクターの声かけを取得する。
    /// ルーティンセッション外からの呼び出しのため、RoutineEngineには一切触れずCharacterEngineだけを使う。
    func confrontTemptation() async -> String {
        guard let dependencies else { return "" }
        let response = await dependencies.characterEngine.respond(
            to: .blockedBehaviorDetected(
                behaviorTitle: currentBehavior?.title ?? "",
                counterMessage: currentBehavior?.counterMessage ?? "",
                reason: currentBehavior?.reason ?? "",
                alternativeAction: currentBehavior?.alternativeAction ?? ""
            )
        )
        return response.text
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
