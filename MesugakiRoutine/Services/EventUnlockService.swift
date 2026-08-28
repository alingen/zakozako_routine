import Foundation

/// イベントの「解放」を司る。条件を満たしたイベントを unlocked 状態にするだけで、開始はしない。
/// 解放済み・未完了のイベントは、今日の会話の後やホーム画面からユーザーが任意に開始する。
@MainActor
final class EventUnlockService {
    private let catalog: EventCatalog
    private let progressRepository: EventProgressRepository
    private let metricsProvider: ProgressMetricsProvider

    init(
        catalog: EventCatalog,
        progressRepository: EventProgressRepository,
        metricsProvider: ProgressMetricsProvider
    ) {
        self.catalog = catalog
        self.progressRepository = progressRepository
        self.metricsProvider = metricsProvider
    }

    /// 現在の進捗で解放条件を満たしたイベントを解放する(まだ解放していないものだけ)。
    /// ルーティン完了後・やらないこと達成後・画面表示時など、こまめに呼んで問題ない(冪等)。
    func refreshUnlocks() {
        let metrics = metricsProvider.current()
        for event in catalog.allEvents where !progressRepository.isUnlocked(event.eventId) {
            if event.unlockConditions.isSatisfied(by: metrics) {
                progressRepository.markUnlocked(eventId: event.eventId)
            }
        }
    }

    /// 解放済みで未完了のイベントを、カタログ定義順で1つ返す。
    /// 今日の会話の後やホーム画面の「話したいことがあるみたい」導線で使う。
    func nextPresentableEvent() -> EventDefinition? {
        catalog.allEvents.first { event in
            progressRepository.isUnlocked(event.eventId) && !progressRepository.isCompleted(event.eventId)
        }
    }

    /// 解放済み・未完了のイベント一覧(デバッグ/一覧表示用)。
    func presentableEvents() -> [EventDefinition] {
        catalog.allEvents.filter { event in
            progressRepository.isUnlocked(event.eventId) && !progressRepository.isCompleted(event.eventId)
        }
    }
}
