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
