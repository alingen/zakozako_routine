import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryConditionEvaluatorTests: XCTestCase {
    private var container: ModelContainer?

    func testComparisonOperators() throws {
        let evaluator = StoryConditionEvaluator()
        let metrics = StoryProgressMetrics(
            continuousDays: 0,
            profileValues: ["score": "10"]
        )
        let cases: [(operatorName: String, threshold: String, expected: Bool)] = [
            ("eq", "10", true),
            ("ne", "9", true),
            ("gt", "9", true),
            ("gte", "10", true),
            ("lt", "11", true),
            ("lte", "10", true),
            ("exists", "", true),
        ]

        for testCase in cases {
            let condition = try decodeCondition(
                type: "profile",
                key: "score",
                operatorName: testCase.operatorName,
                threshold: testCase.threshold
            )
            XCTAssertEqual(
                evaluator.evaluate(condition: condition, metrics: metrics).satisfied,
                testCase.expected,
                "operator \(testCase.operatorName)"
            )
        }

        let missing = try decodeCondition(
            type: "profile",
            key: "missing",
            operatorName: "exists",
            threshold: ""
        )
        XCTAssertFalse(evaluator.evaluate(condition: missing, metrics: metrics).satisfied)
    }

    func testUnknownConditionTypeAndOperatorFailClosed() throws {
        let evaluator = StoryConditionEvaluator()
        let metrics = StoryProgressMetrics(
            continuousDays: 0,
            profileValues: ["score": "10"]
        )
        let unknownType = try decodeCondition(
            type: "future_metric",
            key: "score",
            operatorName: "eq",
            threshold: "10"
        )
        let unknownOperator = try decodeCondition(
            type: "profile",
            key: "score",
            operatorName: "contains",
            threshold: "1"
        )

        let typeResult = evaluator.evaluate(condition: unknownType, metrics: metrics)
        let operatorResult = evaluator.evaluate(condition: unknownOperator, metrics: metrics)

        XCTAssertFalse(typeResult.satisfied)
        XCTAssertNotNil(typeResult.diagnostic)
        XCTAssertFalse(operatorResult.satisfied)
        XCTAssertNotNil(operatorResult.diagnostic)
    }

    func testMultipleEventConditionsUseANDSemantics() throws {
        let event = try decodeEvent(
            conditionsJSON:
                """
                [
                  {
                    "conditionType": "profile",
                    "conditionKey": "score",
                    "operator": "gte",
                    "threshold": "10"
                  },
                  {
                    "conditionType": "profile",
                    "conditionKey": "route",
                    "operator": "eq",
                    "threshold": "accepted"
                  }
                ]
                """
        )
        let evaluator = StoryConditionEvaluator()

        let oneConditionFails = evaluator.evaluate(
            event: event,
            metrics: StoryProgressMetrics(
                continuousDays: 0,
                profileValues: ["score": "10", "route": "declined"]
            )
        )
        let allConditionsPass = evaluator.evaluate(
            event: event,
            metrics: StoryProgressMetrics(
                continuousDays: 0,
                profileValues: ["score": "10", "route": "accepted"]
            )
        )

        XCTAssertFalse(oneConditionFails.conditionsSatisfied)
        XCTAssertFalse(oneConditionFails.isSatisfied)
        XCTAssertTrue(allConditionsPass.conditionsSatisfied)
        XCTAssertTrue(allConditionsPass.isSatisfied)
    }

    func testContinuousDaysStreakUsesRoutineMetric() throws {
        let condition = try decodeCondition(
            type: "streak",
            key: "continuous_days",
            operatorName: "gte",
            threshold: "7"
        )
        let evaluator = StoryConditionEvaluator()

        XCTAssertFalse(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(continuousDays: 6)
            ).satisfied
        )
        XCTAssertTrue(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(continuousDays: 7)
            ).satisfied
        )
    }

    func testCumulativeAchievementDaysUsesRoutineMetric() throws {
        let condition = try decodeCondition(
            type: "achievement",
            key: "cumulative_days",
            operatorName: "gte",
            threshold: "7"
        )
        let evaluator = StoryConditionEvaluator()

        XCTAssertFalse(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(
                    continuousDays: 99,
                    cumulativeAchievementDays: 6
                )
            ).satisfied
        )
        XCTAssertTrue(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(
                    continuousDays: 0,
                    cumulativeAchievementDays: 7
                )
            ).satisfied
        )
    }

    func testRelationshipTrustUsesStoryMetric() throws {
        let condition = try decodeCondition(
            type: "relationship",
            key: "trust",
            operatorName: "gte",
            threshold: "10"
        )
        let evaluator = StoryConditionEvaluator()

        XCTAssertFalse(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(continuousDays: 0, trust: 9)
            ).satisfied
        )
        XCTAssertTrue(
            evaluator.evaluate(
                condition: condition,
                metrics: StoryProgressMetrics(continuousDays: 0, trust: 10)
            ).satisfied
        )
    }

    func testDisplayTextIsUserFacingWithoutCMSKeys() throws {
        let evaluator = StoryConditionEvaluator()
        let metrics = StoryProgressMetrics(continuousDays: 1, cumulativeAchievementDays: 2)
        let cases: [(type: String, key: String, operatorName: String, threshold: String, expected: String)] = [
            ("achievement", "cumulative_days", "gte", "3", "約束を累計3日達成"),
            ("streak", "continuous_days", "gte", "5", "約束を5日連続で達成"),
            ("streak", "streak_days", "gt", "4", "約束を5日連続で達成"),
            ("relationship", "trust", "gte", "10", "信頼度を10まで上げる"),
            ("event", "event_completed", "exists", "event_prologue", "前のストーリーを読む"),
            ("profile", "favorite_food", "eq", "curry", "ストーリーを進めると解放"),
            ("future_metric", "score", "gte", "3", "ストーリーを進めると解放"),
        ]

        for testCase in cases {
            let condition = try decodeCondition(
                type: testCase.type,
                key: testCase.key,
                operatorName: testCase.operatorName,
                threshold: testCase.threshold
            )
            let text = evaluator.evaluate(condition: condition, metrics: metrics).displayText
            XCTAssertEqual(text, testCase.expected, "\(testCase.type)/\(testCase.key)")
            XCTAssertFalse(text.contains(testCase.key), "CMS key leaked: \(text)")
        }
    }

    func testConditionProgressTextIsOnlyShownForNumericValues() {
        let numeric = StoryConditionPresentation(
            id: "days",
            text: "約束を累計3日達成",
            currentValue: "2",
            targetValue: "3",
            isSatisfied: false
        )
        let eventID = StoryConditionPresentation(
            id: "event",
            text: "前のストーリーを読む",
            currentValue: "event_prologue",
            targetValue: "event_prologue",
            isSatisfied: true
        )

        XCTAssertEqual(numeric.progressText, "2 / 3")
        XCTAssertNil(eventID.progressText)
    }

    func testUnlockRemainsMonotonicWhenConditionLaterBecomesFalse() throws {
        let content = try decodeContent(
            conditionsJSON:
                """
                [
                  {
                    "conditionType": "streak",
                    "conditionKey": "continuous_days",
                    "operator": "gte",
                    "threshold": "5"
                  }
                ]
                """
        )
        let contentRepository = try StoryContentRepository(content: content)
        let stateRepository = try makeStateRepository()
        let metricsProvider = MutableStoryMetricsProvider(
            metrics: StoryProgressMetrics(continuousDays: 5)
        )
        let service = StoryUnlockService(
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            metricsProvider: metricsProvider
        )
        let firstDate = Date(timeIntervalSince1970: 1_700_001_000)
        let first = try service.refreshUnlocks(at: firstDate)
        let originalUnlockedAt = try stateRepository.eventProgress(for: "event_condition_test")?.unlockedAt

        metricsProvider.metrics = StoryProgressMetrics(continuousDays: 0)
        let second = try service.refreshUnlocks(at: firstDate.addingTimeInterval(86_400))
        let persisted = try XCTUnwrap(
            stateRepository.eventProgress(for: "event_condition_test")
        )

        XCTAssertEqual(first.newlyUnlockedEventIds, ["event_condition_test"])
        XCTAssertTrue(try XCTUnwrap(first.events.first).isUnlocked)
        XCTAssertTrue(second.newlyUnlockedEventIds.isEmpty)
        XCTAssertTrue(try XCTUnwrap(second.events.first).isUnlocked)
        XCTAssertFalse(try XCTUnwrap(second.events.first).evaluation.isSatisfied)
        XCTAssertEqual(persisted.unlockedAt, originalUnlockedAt)
    }

    func testDeniedAccessDoesNotLoseAnExactCMSUnlockMilestone() throws {
        let content = try decodeContent(
            conditionsJSON:
                """
                [
                  {
                    "conditionType": "streak",
                    "conditionKey": "continuous_days",
                    "operator": "eq",
                    "threshold": "1"
                  }
                ]
                """
        )
        let contentRepository = try StoryContentRepository(content: content)
        let stateRepository = try makeStateRepository()
        let metricsProvider = MutableStoryMetricsProvider(
            metrics: StoryProgressMetrics(continuousDays: 1)
        )
        let deniedService = StoryUnlockService(
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            metricsProvider: metricsProvider,
            evaluator: StoryConditionEvaluator(accessPolicy: DeniedStoryAccessPolicy())
        )

        let deniedAtMilestone = try deniedService.refreshUnlocks()

        XCTAssertEqual(deniedAtMilestone.newlyUnlockedEventIds, ["event_condition_test"])
        XCTAssertTrue(try XCTUnwrap(deniedAtMilestone.events.first).isUnlocked)
        XCTAssertFalse(try XCTUnwrap(deniedAtMilestone.events.first).canPlay)

        metricsProvider.metrics = StoryProgressMetrics(continuousDays: 2)
        let allowedService = StoryUnlockService(
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            metricsProvider: metricsProvider
        )
        let allowedAfterMilestone = try allowedService.evaluations()

        XCTAssertTrue(try XCTUnwrap(allowedAfterMilestone.first).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(allowedAfterMilestone.first).canPlay)
        XCTAssertFalse(try XCTUnwrap(allowedAfterMilestone.first).evaluation.conditionsSatisfied)
    }

    private func makeStateRepository() throws -> StoryStateRepository {
        let schema = Schema([
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        return StoryStateRepository(context: container.mainContext)
    }

    private func decodeCondition(
        type: String,
        key: String,
        operatorName: String,
        threshold: String
    ) throws -> StoryCondition {
        let object: [String: String] = [
            "conditionType": type,
            "conditionKey": key,
            "operator": operatorName,
            "threshold": threshold,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(StoryCondition.self, from: data)
    }

    private func decodeEvent(conditionsJSON: String) throws -> StoryEvent {
        let json =
            """
            {
              "eventId": "event_condition_test",
              "eventType": "middle_event",
              "title": "condition fixture",
              "entryScenarioId": "scenario_condition_test",
              "priority": 1,
              "repeatable": false,
              "cooldownDays": 0,
              "conditions": \(conditionsJSON)
            }
            """
        return try JSONDecoder().decode(StoryEvent.self, from: Data(json.utf8))
    }

    private func decodeContent(conditionsJSON: String) throws -> StoryContentBundle {
        let json =
            """
            {
              "scenarios": [],
              "choiceGroups": [],
              "interactions": [],
              "events": [
                {
                  "eventId": "event_condition_test",
                  "eventType": "middle_event",
                  "title": "condition fixture",
                  "entryScenarioId": "scenario_condition_test",
                  "priority": 1,
                  "repeatable": false,
                  "cooldownDays": 0,
                  "conditions": \(conditionsJSON)
                }
              ]
            }
            """
        return try JSONDecoder().decode(StoryContentBundle.self, from: Data(json.utf8))
    }
}

private struct DeniedStoryAccessPolicy: StoryAccessPolicy {
    func decision(for event: StoryEvent) -> StoryAccessDecision {
        .denied(reason: "test")
    }
}

@MainActor
private final class MutableStoryMetricsProvider: StoryProgressMetricsProviding {
    var metrics: StoryProgressMetrics

    init(metrics: StoryProgressMetrics) {
        self.metrics = metrics
    }

    func current(at date: Date, calendar: Calendar) throws -> StoryProgressMetrics {
        metrics
    }
}

final class InteractionStoryProgressPresentationTests: XCTestCase {
    func testEpisodeZeroUsesPrologueLabel() {
        let item = StoryListItemPresentation(
            id: "prologue",
            title: "プロローグ",
            chapterId: "chapter_01",
            episodeOrder: 0,
            backgroundAssetId: nil,
            isUnlocked: true,
            isNew: true,
            isRead: false,
            conditions: []
        )

        XCTAssertEqual(item.episodeLabel, "プロローグ")
    }

    func testEmptyChaptersHaveZeroProgress() {
        let progress = InteractionStoryProgressPresentation.make(chapters: [], evaluations: [])
        XCTAssertEqual(progress, .empty)
        XCTAssertEqual(progress.progressFraction, 0)
    }

    func testProgressCountsReadStoriesWithinFirstUnfinishedChapter() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("a", isRead: true), story("b")])],
            evaluations: []
        )
        XCTAssertEqual(progress.chapterTitle, "チャプター 1")
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertEqual(progress.totalCount, 2)
        XCTAssertEqual(progress.progressFraction, 0.5)
    }

    func testFinishingChapterMovesProgressToNextChapter() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [
                chapter("1", stories: [story("a", isRead: true)]),
                chapter("2", stories: [story("b"), story("c"), story("d")]),
            ],
            evaluations: []
        )
        XCTAssertEqual(progress.chapterTitle, "チャプター 2")
        XCTAssertEqual(progress.completedCount, 0)
        XCTAssertEqual(progress.totalCount, 3)
        XCTAssertEqual(progress.progressFraction, 0)
    }

    func testAllReadRetainsLastChapterAndShowsCompletion() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [
                chapter("1", stories: [story("a", isRead: true)]),
                chapter("2", stories: [story("b", isRead: true), story("c", isRead: true)]),
            ],
            evaluations: []
        )
        XCTAssertEqual(progress.chapterTitle, "チャプター 2")
        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.totalCount, 2)
        XCTAssertEqual(progress.progressFraction, 1)
        XCTAssertEqual(progress.nextStoryText, "すべてのストーリーを読み終えました")
    }

    func testPrologueIsCountedSeparatelyLikeTheStoryList() {
        let stories = [
            StoryListItemPresentation(
                id: "prologue", title: "prologue", chapterId: "1", episodeOrder: 0,
                backgroundAssetId: nil, isUnlocked: true, isNew: false, isRead: true, conditions: []
            ),
            StoryListItemPresentation(
                id: "ep1", title: "ep1", chapterId: "1", episodeOrder: 1,
                backgroundAssetId: nil, isUnlocked: true, isNew: false, isRead: true, conditions: []
            ),
            StoryListItemPresentation(
                id: "ep2", title: "ep2", chapterId: "1", episodeOrder: 2,
                backgroundAssetId: nil, isUnlocked: true, isNew: false, isRead: false, conditions: []
            ),
        ]
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: stories)],
            evaluations: []
        )
        XCTAssertEqual(progress.chapterTitle, "チャプター 1")
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertEqual(progress.totalCount, 2)
    }

    func testUnlockedUnreadStoryShowsAvailabilityNotRemainingDays() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("next", isUnlocked: true)])],
            evaluations: []
        )
        XCTAssertEqual(progress.nextStoryText, "次のストーリーを読めます")
    }

    func testNextStoryTitleAndNewFlagForMiniCard() {
        let stories = [
            StoryListItemPresentation(
                id: "ep1", title: "はじめての約束", chapterId: "1", episodeOrder: 1,
                backgroundAssetId: nil, isUnlocked: true, isNew: false, isRead: true, conditions: []
            ),
            StoryListItemPresentation(
                id: "ep2", title: "放課後の寄り道", chapterId: "1", episodeOrder: 2,
                backgroundAssetId: nil, isUnlocked: true, isNew: true, isRead: false, conditions: []
            ),
        ]
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: stories)],
            evaluations: []
        )
        XCTAssertEqual(progress.nextStoryTitle, "第2話 放課後の寄り道")
        XCTAssertTrue(progress.nextStoryIsNew)
    }

    func testLockedNextStoryIsNotMarkedNew() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("locked")])],
            evaluations: []
        )
        XCTAssertNotNil(progress.nextStoryTitle)
        XCTAssertFalse(progress.nextStoryIsNew)
    }

    func testAllReadHasNoNextStoryTitle() {
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("a", isRead: true)])],
            evaluations: []
        )
        XCTAssertNil(progress.nextStoryTitle)
        XCTAssertFalse(progress.nextStoryIsNew)
    }

    func testDayThresholdDisplaysGenuineRemainingDays() {
        let condition = StoryCondition(
            conditionType: "streak", conditionKey: "continuous_days", operator: .greaterThan,
            threshold: "7"
        )
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("next")])],
            evaluations: [evaluation(conditions: [condition], continuousDays: 5)]
        )
        XCTAssertEqual(progress.nextStoryText, "次のストーリーまで あと3日")
    }

    func testTrustBlockerIsNotMisrepresentedAsOnlyADayCountdown() {
        let conditions = [
            StoryCondition(
                conditionType: "streak", conditionKey: "continuous_days", operator: .greaterThanOrEqual,
                threshold: "7"
            ),
            StoryCondition(
                conditionType: "relationship", conditionKey: "trust", operator: .greaterThanOrEqual,
                threshold: "10"
            ),
        ]
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("next")])],
            evaluations: [evaluation(conditions: conditions, continuousDays: 5, trust: 6)]
        )
        XCTAssertEqual(progress.nextStoryText, "次のストーリーまで あと2日・信頼度あと4")
    }

    func testUnmeasurableOrOtherBlockersDoNotInventRemainingDays() {
        let days = StoryCondition(
            conditionType: "streak", conditionKey: "continuous_days", operator: .greaterThanOrEqual,
            threshold: "7"
        )
        let other = StoryCondition(
            conditionType: "story_flag", conditionKey: "accepted", operator: .exists,
            threshold: ""
        )
        let progress = InteractionStoryProgressPresentation.make(
            chapters: [chapter("1", stories: [story("next")])],
            evaluations: [evaluation(conditions: [days, other], continuousDays: 5)]
        )
        XCTAssertEqual(progress.nextStoryText, "解放条件を確認してください")
    }

    private func chapter(_ id: String, stories: [StoryListItemPresentation]) -> StoryChapterPresentation {
        StoryChapterPresentation(id: id, title: "チャプター \(id)", stories: stories)
    }

    private func story(
        _ id: String,
        isRead: Bool = false,
        isUnlocked: Bool = false
    ) -> StoryListItemPresentation {
        StoryListItemPresentation(
            id: id, title: id, chapterId: "fixture", episodeOrder: nil, backgroundAssetId: nil,
            isUnlocked: isUnlocked, isNew: false, isRead: isRead, conditions: []
        )
    }

    private func evaluation(
        conditions: [StoryCondition],
        continuousDays: Int,
        trust: Int = 0
    ) -> StoryEventUnlockEvaluation {
        let event = StoryEvent(
            eventId: "next", eventType: .middle, title: "next", entryScenarioId: "fixture",
            priority: 1, repeatable: false, cooldownDays: 0, background: nil, advancesToPhase: nil,
            chapterId: "fixture", episodeOrder: nil, storyCategory: .main, conditions: conditions,
            notes: nil
        )
        return StoryEventUnlockEvaluation(
            event: event,
            evaluation: StoryConditionEvaluator().evaluate(
                event: event,
                metrics: StoryProgressMetrics(continuousDays: continuousDays, trust: trust)
            ),
            isUnlocked: false,
            wasNewlyUnlocked: false
        )
    }
}
