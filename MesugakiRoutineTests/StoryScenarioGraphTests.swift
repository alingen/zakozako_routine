import XCTest
@testable import MesugakiRoutine

final class StoryScenarioGraphTests: XCTestCase {
    func testSuccessorPrefersChoiceThenNodeLinkThenLineOrder() throws {
        let scenario = try decodeScenario(
            """
            {
              "scenarioId": "graph_precedence",
              "scenarioType": "small_event",
              "nodes": [
                {
                  "nodeId": "n1",
                  "lineOrder": 1,
                  "speaker": "character",
                  "messageType": "choice",
                  "nextNodeId": "n3"
                },
                {
                  "nodeId": "n2",
                  "lineOrder": 2,
                  "speaker": "character",
                  "messageType": "text"
                },
                {
                  "nodeId": "n3",
                  "lineOrder": 3,
                  "speaker": "character",
                  "messageType": "text"
                },
                {
                  "nodeId": "n4",
                  "lineOrder": 4,
                  "speaker": "character",
                  "messageType": "text"
                }
              ]
            }
            """
        )
        let choice = try decodeChoice(
            """
            {
              "choiceOrder": 1,
              "label": "branch",
              "nextNodeId": "n2"
            }
            """
        )
        let graph = try StoryScenarioGraph(scenario: scenario)

        let n1 = try XCTUnwrap(graph.node(id: "n1"))
        let n3 = try XCTUnwrap(graph.node(id: "n3"))

        XCTAssertEqual(try graph.successor(after: n1, selectedChoice: choice)?.nodeId, "n2")
        XCTAssertEqual(try graph.successor(after: n1)?.nodeId, "n3")
        XCTAssertEqual(try graph.successor(after: n3)?.nodeId, "n4")
    }

    func testNextVisibleNodeSkipsNodesOutsideCurrentPhase() throws {
        let scenario = try decodeScenario(
            """
            {
              "scenarioId": "phase_filter",
              "scenarioType": "middle_event",
              "nodes": [
                {
                  "nodeId": "start",
                  "lineOrder": 1,
                  "speaker": "character",
                  "messageType": "text"
                },
                {
                  "nodeId": "later_phase",
                  "lineOrder": 2,
                  "speaker": "character",
                  "messageType": "text",
                  "minPhase": 2,
                  "nextNodeId": "visible"
                },
                {
                  "nodeId": "visible",
                  "lineOrder": 3,
                  "speaker": "character",
                  "messageType": "text"
                }
              ]
            }
            """
        )
        let graph = try StoryScenarioGraph(scenario: scenario)
        let start = try XCTUnwrap(graph.node(id: "start"))

        XCTAssertEqual(
            try graph.nextVisibleNode(after: start, phase: 1)?.nodeId,
            "visible"
        )
        XCTAssertEqual(
            try graph.nextVisibleNode(after: start, phase: 2)?.nodeId,
            "later_phase"
        )
    }

    func testDanglingTargetIsReportedAsRecoverableGraphError() throws {
        let scenario = try decodeScenario(
            """
            {
              "scenarioId": "dangling",
              "scenarioType": "large_event",
              "nodes": [
                {
                  "nodeId": "start",
                  "lineOrder": 1,
                  "speaker": "character",
                  "messageType": "text",
                  "nextNodeId": "missing"
                }
              ]
            }
            """
        )
        let graph = try StoryScenarioGraph(scenario: scenario)
        let start = try XCTUnwrap(graph.node(id: "start"))

        XCTAssertThrowsError(try graph.successor(after: start)) { error in
            XCTAssertEqual(
                error as? StoryScenarioGraphError,
                .danglingTarget(fromNodeId: "start", targetNodeId: "missing")
            )
        }
    }

    func testFilteredAutomaticCycleIsReportedWithoutHanging() throws {
        let scenario = try decodeScenario(
            """
            {
              "scenarioId": "filtered_cycle",
              "scenarioType": "daily",
              "nodes": [
                {
                  "nodeId": "n1",
                  "lineOrder": 1,
                  "speaker": "character",
                  "messageType": "text",
                  "nextNodeId": "n2",
                  "minPhase": 2
                },
                {
                  "nodeId": "n2",
                  "lineOrder": 2,
                  "speaker": "character",
                  "messageType": "text",
                  "nextNodeId": "n1",
                  "minPhase": 2
                }
              ]
            }
            """
        )
        let graph = try StoryScenarioGraph(scenario: scenario)

        XCTAssertThrowsError(try graph.firstVisibleNode(phase: 1)) { error in
            guard case .automaticCycle(let nodeIds) = error as? StoryScenarioGraphError else {
                return XCTFail("Expected automaticCycle, got \(error)")
            }
            XCTAssertEqual(nodeIds, ["n1", "n2", "n1"])
        }
    }

    func testOnlyMiddleAndLargeStillFramesUseLandscapePresentation() {
        XCTAssertFalse(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .daily,
                cgAssetID: "cg_test",
                isCompleted: false
            )
        )
        XCTAssertFalse(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .middleEvent,
                cgAssetID: nil,
                isCompleted: false
            )
        )
        XCTAssertTrue(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .middleEvent,
                cgAssetID: "cg_test",
                isCompleted: false
            )
        )
        XCTAssertTrue(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .largeEvent,
                cgAssetID: "cg_test",
                isCompleted: false
            )
        )
        XCTAssertFalse(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .largeEvent,
                cgAssetID: "cg_test",
                isCompleted: true
            )
        )
        XCTAssertFalse(
            StoryPresentationOrientationPolicy.usesLandscape(
                scenarioType: .unknown("future_event"),
                cgAssetID: "cg_test",
                isCompleted: false
            )
        )
    }

    func testOnlyMiddleAndLargeEventsReturnToMenuAutomaticallyAfterCompletion() {
        XCTAssertFalse(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .daily)
        )
        XCTAssertFalse(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .smallEvent)
        )
        XCTAssertTrue(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .middleEvent)
        )
        XCTAssertTrue(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .largeEvent)
        )
        XCTAssertFalse(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(
                after: .unknown("future_event")
            )
        )
    }

    func testLogIsAvailableOnlyForMiddleAndLargeEvents() {
        XCTAssertFalse(StoryLogPresentationPolicy.isAvailable(for: .daily))
        XCTAssertFalse(StoryLogPresentationPolicy.isAvailable(for: .smallEvent))
        XCTAssertTrue(StoryLogPresentationPolicy.isAvailable(for: .middleEvent))
        XCTAssertTrue(StoryLogPresentationPolicy.isAvailable(for: .largeEvent))
        XCTAssertFalse(
            StoryLogPresentationPolicy.isAvailable(for: .unknown("future_event"))
        )
    }

    func testMiddleAndLargeChatSystemTextUsesADVPresentation() {
        let narration = StoryNode(
            nodeId: "narration",
            lineOrder: 1,
            speaker: "narrator",
            messageType: .text,
            text: "少しして。",
            screenMode: .chat,
            uiVariant: .narration
        )

        XCTAssertTrue(
            EventChatSystemPresentationPolicy.usesADVTextWindow(
                node: narration,
                scenarioType: .middleEvent
            )
        )
        XCTAssertTrue(
            EventChatSystemPresentationPolicy.usesADVTextWindow(
                node: narration,
                scenarioType: .largeEvent
            )
        )
        XCTAssertFalse(
            EventChatSystemPresentationPolicy.usesADVTextWindow(
                node: narration,
                scenarioType: .smallEvent
            )
        )
    }

    func testEmptySystemCommandIsOmittedFromEventChatHistory() {
        let sceneChange = StoryNode(
            nodeId: "scene-change",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            text: "",
            screenMode: .chat,
            uiVariant: .sceneTransition
        )

        XCTAssertTrue(
            EventChatSystemPresentationPolicy.omitsFromChatHistory(
                node: sceneChange,
                scenarioType: .middleEvent
            )
        )
        XCTAssertFalse(
            EventChatSystemPresentationPolicy.omitsFromChatHistory(
                node: sceneChange,
                scenarioType: .smallEvent
            )
        )
    }

    func testMiddleAndLargeEventsRequireExplicitChatEntry() {
        XCTAssertEqual(
            StoryScreenModeTransitionPolicy.resolveRowMode(
                .chat,
                currentMode: .adv,
                scenarioType: .middleEvent,
                hasExplicitTransition: false
            ),
            .adv
        )
        XCTAssertEqual(
            StoryScreenModeTransitionPolicy.resolveRowMode(
                .chat,
                currentMode: .adv,
                scenarioType: .largeEvent,
                hasExplicitTransition: false
            ),
            .adv
        )
        XCTAssertEqual(
            StoryScreenModeTransitionPolicy.resolveRowMode(
                .chat,
                currentMode: .chat,
                scenarioType: .middleEvent,
                hasExplicitTransition: false
            ),
            .chat
        )
        XCTAssertEqual(
            StoryScreenModeTransitionPolicy.resolveRowMode(
                .chat,
                currentMode: .adv,
                scenarioType: .smallEvent,
                hasExplicitTransition: false
            ),
            .chat
        )
        XCTAssertEqual(
            StoryScreenModeTransitionPolicy.resolveRowMode(
                .chat,
                currentMode: .adv,
                scenarioType: .middleEvent,
                hasExplicitTransition: true
            ),
            .chat
        )
    }

    private func decodeScenario(_ json: String) throws -> StoryScenario {
        try JSONDecoder().decode(StoryScenario.self, from: Data(json.utf8))
    }

    private func decodeChoice(_ json: String) throws -> StoryChoice {
        try JSONDecoder().decode(StoryChoice.self, from: Data(json.utf8))
    }
}
