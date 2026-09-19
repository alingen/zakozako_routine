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
    private(set) var storyProgress: InteractionStoryProgressPresentation = .empty
    private(set) var todayConversationTitle = "今日の会話"
    private(set) var todayConversationDetail = "日付ごとに入れ替わる、莉央との短い会話"
    private(set) var todayConversationIsAvailable = false
    private(set) var todayConversationIsUnread = false
    private(set) var todayConversationHasResumePosition = false
    private(set) var interactionComment: InteractionComment?
    private(set) var loadError: String?
    private(set) var activeLaunch: StoryLaunchRequest?

    private var dependencies: AppDependencies?
    private var todayScenario: StoryScenario?
    private var todayPlaybackKey: String?

    func configure(context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
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
            storyProgress = .make(chapters: mainChapters, evaluations: refresh.events)
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
        // 「あとで読む」でTodayカードへ載せた初回会話は、通常の日付別会話ではない。
        // タップ直前の再設定で消さず、そのまま専用キーで再生する。
        let isDeferredOnboardingConversation = todayPlaybackKey?.hasPrefix("daily:onboarding:") == true
        if !isDeferredOnboardingConversation,
           let dependencies,
           let content = dependencies.storyContentRepository {
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
            playbackKey: todayPlaybackKey
                ?? DailyConversationSchedule.playbackKey(on: now, calendar: calendar),
            scenario: scenario,
            event: nil
        )
    }

    /// 「あとで読む」または途中で閉じた初回会話を、通常の今日の会話カードへ載せる。
    /// 初回に確定した識別子を使うため、日付が変わっても別の会話へ入れ替わらない。
    func offerDeferredOnboardingConversationIfNeeded(
        identity: OnboardingConversationIdentity,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let dependencies,
              let content = dependencies.storyContentRepository,
              let launch = Self.onboardingConversationLaunch(
                identity: identity,
                title: todayConversationTitle,
                dailyScenarios: content.dailyScenarios,
                checkpointForPlaybackKey: {
                    try? dependencies.storyStateRepository.checkpoint(for: $0)
                }
              ) else { return }

        todayScenario = launch.scenario
        todayPlaybackKey = launch.playbackKey
        todayConversationIsAvailable = true
        let checkpoint = try? dependencies.storyStateRepository.checkpoint(for: launch.playbackKey)
        todayConversationIsUnread = checkpoint?.isCompleted != true
        todayConversationHasResumePosition = checkpoint?.currentNodeId != nil
            && checkpoint?.isCompleted == false
    }

    /// Opens the conversation requested explicitly by the onboarding flow.
    /// A calendar-scheduled conversation keeps the same priority and playback
    /// key as the normal Today card. Only when no conversation is scheduled do
    /// we fall back to an unread, unscheduled daily scenario with a stable key.
    @discardableResult
    func openOnboardingConversation(
        identity: OnboardingConversationIdentity,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let dependencies,
              let content = dependencies.storyContentRepository,
              let launch = Self.onboardingConversationLaunch(
                identity: identity,
                title: todayConversationTitle,
                dailyScenarios: content.dailyScenarios,
                checkpointForPlaybackKey: {
                    try? dependencies.storyStateRepository.checkpoint(for: $0)
                }
              ) else {
            return false
        }

        activeLaunch = launch
        return true
    }

    func isPlaybackCompleted(_ playbackKey: String) -> Bool {
        guard let dependencies else { return false }
        return (try? dependencies.storyStateRepository.checkpoint(for: playbackKey))?.isCompleted == true
    }

    static func onboardingConversationIdentity(for launch: StoryLaunchRequest) -> OnboardingConversationIdentity {
        OnboardingConversationIdentity(
            scenarioID: launch.scenario.scenarioId,
            playbackKey: launch.playbackKey
        )
    }

    static func onboardingConversationLaunch(
        identity: OnboardingConversationIdentity,
        title: String = "今日の会話",
        dailyScenarios: [StoryScenario],
        checkpointForPlaybackKey: (String) -> StoryPlaybackCheckpoint?
    ) -> StoryLaunchRequest? {
        guard checkpointForPlaybackKey(identity.playbackKey)?.isCompleted != true,
              let scenario = dailyScenarios.first(where: {
                  $0.scenarioType == .daily && $0.scenarioId == identity.scenarioID
              }) else {
            return nil
        }

        return StoryLaunchRequest(
            title: title,
            playbackKey: identity.playbackKey,
            scenario: scenario,
            event: nil
        )
    }

    static func onboardingConversationLaunch(
        title: String = "今日の会話",
        now: Date = .now,
        calendar: Calendar = .current,
        dailyScenarios: [StoryScenario],
        checkpointForPlaybackKey: (String) -> StoryPlaybackCheckpoint?
    ) -> StoryLaunchRequest? {
        if let scheduled = DailyConversationSchedule.scenario(
            on: now,
            from: dailyScenarios,
            calendar: calendar
        ) {
            return StoryLaunchRequest(
                title: title,
                playbackKey: DailyConversationSchedule.playbackKey(
                    on: now,
                    calendar: calendar
                ),
                scenario: scheduled,
                event: nil
            )
        }

        let unscheduled = dailyScenarios.filter { scenario in
            guard scenario.scenarioType == .daily else { return false }
            return !hasText(scenario.calendarDate) && !hasText(scenario.calendarMonthDay)
        }
        guard let scenario = unscheduled.first(where: { $0.scenarioId == "daily_001" })
                ?? unscheduled.first else {
            return nil
        }

        let playbackKey = onboardingPlaybackKey(for: scenario)
        guard checkpointForPlaybackKey(playbackKey)?.isCompleted != true else {
            return nil
        }
        return StoryLaunchRequest(
            title: title,
            playbackKey: playbackKey,
            scenario: scenario,
            event: nil
        )
    }

    private static func onboardingPlaybackKey(for scenario: StoryScenario) -> String {
        "daily:onboarding:\(scenario.scenarioId)"
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectInteractionComment(
        touchArea: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let dependencies, let content = dependencies.storyContentRepository else {
            interactionComment = nil
            return
        }
        let profileValues = (try? dependencies.storyStateRepository.profileValues()) ?? [:]
        interactionComment = InteractionCommentSelector.select(
            from: content.interactions,
            touchArea: touchArea,
            now: now,
            calendar: calendar,
            profileValues: profileValues,
            excluding: interactionComment?.id
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
        guard let scenario = DailyConversationSchedule.scenario(
                on: now,
                from: content.dailyScenarios,
                calendar: calendar
              ) else {
            todayScenario = nil
            todayPlaybackKey = nil
            todayConversationIsAvailable = false
            todayConversationIsUnread = false
            todayConversationHasResumePosition = false
            return
        }

        let key = DailyConversationSchedule.playbackKey(on: now, calendar: calendar)
        todayScenario = scenario
        todayPlaybackKey = key
        todayConversationIsAvailable = true
        let checkpoint = try? state.checkpoint(for: key)
        todayConversationIsUnread = checkpoint?.isCompleted != true
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
        storyProgress = .empty
        interactionComment = nil
        todayScenario = nil
        todayPlaybackKey = nil
        todayConversationIsAvailable = false
        todayConversationIsUnread = false
        todayConversationHasResumePosition = false
        loadError = error
    }
}
