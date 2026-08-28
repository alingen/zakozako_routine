import Foundation

/// イベント解放条件の判定に使う、現在のユーザー進捗のスナップショット。
struct ProgressMetrics {
    /// 信頼度ポイント(TrustState.points の生値。フリートーク話題ゲートは通さない)。
    let trustPoints: Int
    /// ルーティンの連続達成日数。
    let streakDays: Int
    /// 「やらないこと」を守れた累積回数。
    let blockedProtectedCount: Int
    /// 「やらないこと」を卒業(14日達成)した個数。
    let masteredCount: Int
    /// 関係性フェーズ(RelationshipState.phase)。
    let relationshipPhase: Int
    /// 完了済みのイベントid。
    let completedEventIds: Set<String>
}

/// 各リポジトリ/ストアから `ProgressMetrics` を組み立てる。
@MainActor
struct ProgressMetricsProvider {
    let sessionRepository: RoutineSessionRepository
    let trustRepository: TrustRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let eventProgressRepository: EventProgressRepository
    let relationshipRepository: RelationshipRepository

    func current() -> ProgressMetrics {
        ProgressMetrics(
            trustPoints: trustRepository.points,
            streakDays: StreakCalculator.currentStreak(sessions: sessionRepository.fetchAllSessions()),
            blockedProtectedCount: AppSettingsStore.blockedBehaviorProtectedCount,
            masteredCount: blockedBehaviorRepository.fetchMastered().count,
            relationshipPhase: relationshipRepository.phase,
            completedEventIds: Set(
                eventProgressRepository.fetchAll().filter(\.isCompleted).map(\.eventId)
            )
        )
    }
}
