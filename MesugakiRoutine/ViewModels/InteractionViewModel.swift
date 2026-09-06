import Foundation
import Observation
import SwiftData

struct StoryLaunchRequest: Identifiable {
    let title: String
    let playbackKey: String
    let scenario: StoryScenario
    let event: StoryEvent?

    var id: String { playbackKey }
}

@Observable
@MainActor
final class InteractionViewModel {
    private(set) var mainChapters: [StoryChapterPresentation] = []
    private(set) var subChapters: [StoryChapterPresentation] = []
    private(set) var memories: [StoryMemoryPresentation] = []
    private(set) var todayConversationTitle = "今日の会話"
    private(set) var todayConversationDetail = "日付ごとに入れ替わる、莉央との短い会話"
    private(set) var todayConversationIsAvailable = false
    private(set) var todayConversationHasResumePosition = false
    private(set) var loadError: String?
    private(set) var activeLaunch: StoryLaunchRequest?

    private var dependencies: AppDependencies?
    private var todayScenario: StoryScenario?

    func configure(context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        if AppSettingsStore.dailyConversationAnchorDate == nil {
            AppSettingsStore.dailyConversationAnchorDate = AppDay.startOfDay(for: now, calendar: calendar)
        }
        reload(now: now, calendar: calendar)
    }

    func reload(now: Date = .now, calendar: Calendar = .current) {
        guard let dependencies else { return }
        guard let content = dependencies.storyContentRepository,
              let unlockService = dependencies.storyUnlockService else {
            clearContent(error: "ストーリーデータを読み込めませんでした。scenario-syncの生成物を確認してください。")
            return
        }

        do {
            let refresh = try unlockService.refreshUnlocks(at: now, calendar: calendar)
            let progressById = Dictionary(
                uniqueKeysWithValues: try dependencies.storyStateRepository.eventProgresses()
                    .map { ($0.eventId, $0) }
            )

            mainChapters = makeChapters(
                category: .main,
                evaluations: refresh.events,
                progressById: progressById
            )
            subChapters = makeChapters(
                category: .sub,
                evaluations: refresh.events,
                progressById: progressById
            )
            memories = makeMemories(
                catalog: content.cgCatalog,
                unlocked: try dependencies.storyStateRepository.memoryUnlocks()
            )
            configureToday(
                content: content,
                state: dependencies.storyStateRepository,
                now: now,
                calendar: calendar
            )
            loadError = nil
        } catch {
            loadError = "交流データの状態を更新できませんでした: \(error.localizedDescription)"
        }
    }

    func openToday(now: Date = .now, calendar: Calendar = .current) {
        if let dependencies, let content = dependencies.storyContentRepository {
            configureToday(
                content: content,
                state: dependencies.storyStateRepository,
                now: now,
                calendar: calendar
            )
        }
        guard let scenario = todayScenario else { return }
        activeLaunch = StoryLaunchRequest(
            title: todayConversationTitle,
            playbackKey: DailyConversationSchedule.playbackKey(on: now, calendar: calendar),
            scenario: scenario,
            event: nil
        )
    }

    func openEvent(id: String) {
        guard let dependencies,
              let content = dependencies.storyContentRepository,
              let unlockService = dependencies.storyUnlockService,
              let event = content.event(id: id),
              let scenario = content.scenario(id: event.entryScenarioId),
              let evaluations = try? unlockService.evaluations(),
              evaluations.first(where: { $0.event.eventId == id })?.canPlay == true else {
            return
        }
        activeLaunch = StoryLaunchRequest(
            title: event.title,
            playbackKey: "event:\(event.eventId)",
            scenario: scenario,
            event: event
        )
    }

    func closePlayer(now: Date = .now, calendar: Calendar = .current) {
        activeLaunch = nil
        reload(now: now, calendar: calendar)
    }

    private func configureToday(
        content: StoryContentRepository,
        state: StoryStateRepository,
        now: Date,
        calendar: Calendar
    ) {
        guard let anchor = AppSettingsStore.dailyConversationAnchorDate,
              let index = DailyConversationSchedule.scenarioIndex(
                on: now,
                anchorDate: anchor,
                scenarioCount: content.dailyScenarios.count,
                calendar: calendar
              ),
              content.dailyScenarios.indices.contains(index) else {
            todayScenario = nil
            todayConversationIsAvailable = false
            todayConversationHasResumePosition = false
            return
        }

        let scenario = content.dailyScenarios[index]
        let key = DailyConversationSchedule.playbackKey(on: now, calendar: calendar)
        todayScenario = scenario
        todayConversationIsAvailable = true
        let checkpoint = try? state.checkpoint(for: key)
        todayConversationHasResumePosition = checkpoint?.currentNodeId != nil
            && checkpoint?.isCompleted == false
    }

    private func makeChapters(
        category: StoryCategory,
        evaluations: [StoryEventUnlockEvaluation],
        progressById: [String: StoryEventProgress]
    ) -> [StoryChapterPresentation] {
        let rows = evaluations.filter { $0.event.storyCategory == category }
        var orderedChapterIds: [String] = []
        var grouped: [String: [StoryListItemPresentation]] = [:]

        for row in rows {
            let chapterId = row.event.chapterId ?? "chapter_unspecified"
            if grouped[chapterId] == nil { orderedChapterIds.append(chapterId) }
            let progress = progressById[row.event.eventId]
            grouped[chapterId, default: []].append(
                StoryListItemPresentation(
                    id: row.event.eventId,
                    title: row.event.title,
                    chapterId: chapterId,
                    episodeOrder: row.event.episodeOrder,
                    backgroundAssetId: row.event.background,
                    isUnlocked: row.canPlay,
                    isNew: progress?.isNew == true,
                    isRead: progress?.isRead == true,
                    conditions: row.conditions.map { condition in
                        StoryConditionPresentation(
                            id: condition.id,
                            text: condition.displayText,
                            currentValue: condition.current,
                            targetValue: condition.threshold,
                            isSatisfied: condition.satisfied
                        )
                    }
                )
            )
        }

        return orderedChapterIds.map { chapterId in
            StoryChapterPresentation(
                id: chapterId,
                title: chapterTitle(chapterId),
                stories: (grouped[chapterId] ?? []).sorted { lhs, rhs in
                    let lhsOrder = lhs.episodeOrder ?? Int.max
                    let rhsOrder = rhs.episodeOrder ?? Int.max
                    return lhsOrder != rhsOrder ? lhsOrder < rhsOrder : lhs.id < rhs.id
                }
            )
        }
    }

    private func makeMemories(
        catalog: [StoryCGCatalogEntry],
        unlocked: [StoryMemoryUnlock]
    ) -> [StoryMemoryPresentation] {
        let unlockedIds = Set(unlocked.map(\.assetId))
        return catalog.map { entry in
            StoryMemoryPresentation(
                id: entry.assetId,
                title: entry.eventTitle ?? "ストーリーの思い出",
                assetId: entry.assetId,
                isUnlocked: unlockedIds.contains(entry.assetId)
            )
        }
    }

    private func chapterTitle(_ id: String) -> String {
        let suffix = id.replacingOccurrences(of: "chapter_", with: "")
        return suffix == id ? id : "チャプター \(suffix)"
    }

    private func clearContent(error: String) {
        mainChapters = []
        subChapters = []
        memories = []
        todayScenario = nil
        todayConversationIsAvailable = false
        todayConversationHasResumePosition = false
        loadError = error
    }
}
