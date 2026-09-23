import SwiftUI
import XCTest
@testable import MesugakiRoutine

final class ADVTextLayoutTests: XCTestCase {
    func testStoryDisplayTextConvertsBRForADVAndLogs() {
        let node = StoryNode(
            nodeId: "line-break",
            lineOrder: 1,
            speaker: "rio",
            messageType: .text,
            text: "前半[br]後半"
        )

        XCTAssertEqual(node.storyDisplayText, "前半\n後半")
    }

    func testStoryDisplayTextConvertsSPForADVChatAndLogs() {
        let node = StoryNode(
            nodeId: "space-marker",
            lineOrder: 1,
            speaker: "rio",
            messageType: .text,
            text: "前半[sp]後半"
        )

        XCTAssertEqual(node.storyDisplayText, "前半 後半")
        XCTAssertEqual(ADVTextLayout.formatted("前半[sp]後半"), "前半 後半")
    }

    func testFormatsBRAsAnExplicitLineBreak() {
        XCTAssertEqual(
            ADVTextLayout.formatted("今日はここまで。[br]また明日。"),
            "今日はここまで。\nまた明日。"
        )
    }

    func testWrapsEveryLineAtEighteenCharacters() {
        let firstLine = String(repeating: "あ", count: 19)
        let secondLine = String(repeating: "い", count: 18)
        let formatted = ADVTextLayout.formatted("\(firstLine)[br]\(secondLine)")
        let lines = formatted.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines.map(\.count), [18, 1, 18])
        XCTAssertTrue(lines.allSatisfy { $0.count <= ADVTextLayout.maximumCharactersPerLine })
    }

    func testKeepsConsecutiveExplicitBreaks() {
        XCTAssertEqual(ADVTextLayout.formatted("前[br][br]後"), "前\n\n後")
    }

    func testCountsEmojiSequenceAsOneDisplayedCharacter() {
        let familyEmoji = "👨‍👩‍👧‍👦"
        let formatted = ADVTextLayout.formatted(String(repeating: familyEmoji, count: 19))
        let lines = formatted.split(separator: "\n")

        XCTAssertEqual(lines.map(\.count), [18, 1])
    }

    func testFontSizeGrowsWithWidthAndRemainsWithinReadableBounds() {
        let compact = ADVTextLayout.fontSize(for: 236)
        let regular = ADVTextLayout.fontSize(for: 306)
        let wide = ADVTextLayout.fontSize(for: 1_000)

        XCTAssertGreaterThan(regular, compact)
        XCTAssertEqual(compact, 13, accuracy: 0.01)
        XCTAssertEqual(wide, 22, accuracy: 0.01)
        XCTAssertEqual(ADVTextLayout.maximumLines, 3)
    }

    func testLongDialogueIsPagedWithoutDroppingText() {
        let source = String(repeating: "あ", count: 55)
        let pages = ADVTextLayout.pages(source)

        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(
            pages.allSatisfy {
                $0.split(separator: "\n", omittingEmptySubsequences: false).count <= 3
            }
        )
        XCTAssertEqual(pages.joined().replacingOccurrences(of: "\n", with: ""), source)
    }

    func testAutoAdvanceDelayGrowsWithDialogueAndIsCapped() {
        let shortDelay = ADVPlaybackTiming.autoAdvanceDelayNanoseconds(characterCount: 4)
        let longDelay = ADVPlaybackTiming.autoAdvanceDelayNanoseconds(characterCount: 40)
        let cappedDelay = ADVPlaybackTiming.autoAdvanceDelayNanoseconds(characterCount: 1_000)

        XCTAssertLessThan(shortDelay, longDelay)
        XCTAssertLessThanOrEqual(longDelay, cappedDelay)
        XCTAssertEqual(cappedDelay, 2_790_000_000)
    }

    func testFastForwardClipsCommandWaitWithoutChangingNormalPlayback() {
        XCTAssertEqual(
            StoryPlaybackTiming.commandWaitMilliseconds(1_200, pace: .normal),
            1_200
        )
        XCTAssertEqual(
            StoryPlaybackTiming.commandWaitMilliseconds(1_200, pace: .fastForward),
            60
        )
        XCTAssertEqual(
            StoryPlaybackTiming.commandWaitMilliseconds(40, pace: .fastForward),
            40
        )
    }
}

final class ADVOpeningRevealTimingTests: XCTestCase {
    func testPhaseBoundariesMatchTheADVOpeningTimeline() {
        let cases: [(UInt64, ADVOpeningRevealPhase)] = [
            (0, .scene),
            (299_999_999, .scene),
            (300_000_000, .textBox),
            (499_999_999, .textBox),
            (500_000_000, .text),
            (1_000_000_000, .text),
        ]

        for (elapsed, expected) in cases {
            XCTAssertEqual(
                ADVOpeningRevealTiming.phase(atElapsedNanoseconds: elapsed),
                expected,
                "Unexpected phase at \(elapsed) ns"
            )
        }
    }

    func testPhaseVisibilityIsStaged() {
        XCTAssertFalse(ADVOpeningRevealPhase.blackout.showsScene)
        XCTAssertFalse(ADVOpeningRevealPhase.blackout.showsTextBox)
        XCTAssertFalse(ADVOpeningRevealPhase.blackout.startsTextReveal)

        XCTAssertTrue(ADVOpeningRevealPhase.scene.showsScene)
        XCTAssertFalse(ADVOpeningRevealPhase.scene.showsTextBox)
        XCTAssertFalse(ADVOpeningRevealPhase.scene.startsTextReveal)

        XCTAssertTrue(ADVOpeningRevealPhase.textBox.showsScene)
        XCTAssertTrue(ADVOpeningRevealPhase.textBox.showsTextBox)
        XCTAssertFalse(ADVOpeningRevealPhase.textBox.startsTextReveal)

        XCTAssertTrue(ADVOpeningRevealPhase.text.showsScene)
        XCTAssertTrue(ADVOpeningRevealPhase.text.showsTextBox)
        XCTAssertTrue(ADVOpeningRevealPhase.text.startsTextReveal)
    }

    func testAStoryWithoutAnEventTitleStartsReady() {
        XCTAssertEqual(
            ADVOpeningRevealTiming.initialPhase(hasEventTitle: false),
            .text
        )
        XCTAssertEqual(
            ADVOpeningRevealTiming.initialPhase(hasEventTitle: true),
            .blackout
        )
    }
}

@MainActor
final class ADVStoryRendererRenderingTests: XCTestCase {
    func testMissingBackgroundRendersAsPureBlackInsteadOfAssetPlaceholder() throws {
        let node = StoryNode(
            nodeId: "black-background",
            lineOrder: 1,
            speaker: "narrator",
            messageType: .text,
            text: "暗転後のテキスト",
            screenMode: .adv,
            uiVariant: .narration
        )
        let content = ADVStoryRenderer(
            node: node,
            scenarioType: .prologue,
            backgroundAssetID: nil,
            showsPlaybackControls: false,
            onAdvance: { _ in },
            onSelectChoice: { _ in },
            onDismissModal: {}
        )
        .frame(width: 320, height: 568)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)
        let sample = try XCTUnwrap(
            cgImage.cropping(to: CGRect(x: 12, y: 12, width: 1, height: 1))
        )
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        XCTAssertLessThanOrEqual(rgba[0], 2)
        XCTAssertLessThanOrEqual(rgba[1], 2)
        XCTAssertLessThanOrEqual(rgba[2], 2)
        XCTAssertGreaterThanOrEqual(rgba[3], 253)
    }

    func testEnlargedPortraitDoesNotShiftTheBackgroundLayer() throws {
        let node = StoryNode(
            nodeId: "portrait-layout",
            lineOrder: 1,
            speaker: "rio",
            messageType: .text,
            text: "レイアウト確認",
            screenMode: .adv,
            uiVariant: .dialogue
        )

        func renderedImage(
            size: CGSize,
            portraitAssetID: String?
        ) throws -> UIImage {
            let content = ADVStoryRenderer(
                node: node,
                scenarioType: .prologue,
                backgroundAssetID: "bg_protagonist_living_room",
                portraitAssetID: portraitAssetID,
                showsPlaybackControls: true,
                onAdvance: { _ in },
                onSelectChoice: { _ in },
                onDismissModal: {}
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }

        func rgba(in image: UIImage, x: Int, y: Int) throws -> [UInt8] {
            let cgImage = try XCTUnwrap(image.cgImage)
            let sample = try XCTUnwrap(
                cgImage.cropping(
                    to: CGRect(x: x, y: y, width: 1, height: 1)
                )
            )
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return rgba
        }

        let sizes = [
            CGSize(width: 320, height: 568),
            CGSize(width: 390, height: 844),
            CGSize(width: 428, height: 926)
        ]

        for size in sizes {
            let backgroundOnly = try renderedImage(
                size: size,
                portraitAssetID: nil
            )
            let withEnlargedPortrait = try renderedImage(
                size: size,
                portraitAssetID: "portrait_rio_neutral"
            )
            XCTAssertEqual(backgroundOnly.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(backgroundOnly.size.height, size.height, accuracy: 0.5)
            XCTAssertEqual(withEnlargedPortrait.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(withEnlargedPortrait.size.height, size.height, accuracy: 0.5)
            let backgroundPixel = try rgba(in: backgroundOnly, x: 2, y: 40)
            let portraitPixel = try rgba(in: withEnlargedPortrait, x: 2, y: 40)

            XCTAssertGreaterThan(
                Int(backgroundPixel[0]) + Int(backgroundPixel[1]) + Int(backgroundPixel[2]),
                30,
                "The assertion point must contain the scene background, not the black base."
            )
            for channel in 0..<4 {
                XCTAssertLessThanOrEqual(
                    abs(Int(portraitPixel[channel]) - Int(backgroundPixel[channel])),
                    2,
                    "The enlarged portrait must not move the background layer at width \(size.width)."
                )
            }
        }
    }

    func testDialogueAndPlaybackControlsRenderAtCompactAndRegularWidths() throws {
        let node = StoryNode(
            nodeId: "adv-preview",
            lineOrder: 1,
            speaker: "rio",
            messageType: .text,
            text: "今日はここから始めるよ。[br]まだ諦めてないよね？[br]ちゃんとついてきてね。",
            screenMode: .adv,
            uiVariant: .dialogue
        )

        for size in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844)] {
            let content = ADVStoryRenderer(
                node: node,
                scenarioType: .middleEvent,
                playbackMode: .fastForward,
                isLogAvailable: true,
                onAdvance: { _ in },
                onSelectChoice: { _ in },
                onDismissModal: {}
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)

            let attachment = XCTAttachment(image: image)
            attachment.name = "ADV controls \(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
            let pngData = try XCTUnwrap(image.pngData())
            try pngData.write(
                to: URL(
                    fileURLWithPath: "/tmp/zakozako_adv_controls_\(Int(size.width)).png"
                )
            )
        }
    }
}

final class StoryScenarioGraphTests: XCTestCase {
    func testPrologueIsDecodedAsAFirstClassScenarioAndEventType() {
        XCTAssertEqual(StoryScenarioType(rawValue: "prologue"), .prologue)
        XCTAssertEqual(StoryScenarioType.prologue.rawValue, "prologue")
        XCTAssertEqual(StoryEventType(rawValue: "prologue"), .prologue)
        XCTAssertEqual(StoryEventType.prologue.rawValue, "prologue")
    }

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

    func testPrologueMiddleAndLargeStillFramesUseLandscapePresentation() {
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
                scenarioType: .prologue,
                cgAssetID: "cg_test",
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

    func testPrologueMiddleAndLargeEventsReturnToMenuAutomaticallyAfterCompletion() {
        XCTAssertFalse(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .daily)
        )
        XCTAssertFalse(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .smallEvent)
        )
        XCTAssertTrue(
            StoryCompletionPresentationPolicy.returnsToMenuAutomatically(after: .prologue)
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

    func testDailyConversationSharesChatCompletionAndReservedActionArea() {
        XCTAssertTrue(ChatStoryPresentationPolicy.usesChatCompletion(for: .daily))
        XCTAssertTrue(ChatStoryPresentationPolicy.usesChatCompletion(for: .smallEvent))
        XCTAssertFalse(ChatStoryPresentationPolicy.usesChatCompletion(for: .middleEvent))
        XCTAssertFalse(ChatStoryPresentationPolicy.usesChatCompletion(for: .largeEvent))
        XCTAssertTrue(ChatStoryPresentationPolicy.usesFixedActionArea(for: .daily))
        XCTAssertTrue(ChatStoryPresentationPolicy.usesFixedActionArea(for: .smallEvent))
    }

    func testDailyReplyButtonDoesNotRevealTheUpcomingPlayerLine() {
        let reply = StoryNode(
            nodeId: "reply",
            lineOrder: 1,
            speaker: "user",
            messageType: .text,
            text: "なんで寂しい絵にしようとするの？"
        )
        XCTAssertEqual(
            ChatStoryPresentationPolicy.manualAdvanceLabel(node: reply, scenarioType: .daily),
            "返信する"
        )
        XCTAssertTrue(ChatStoryPresentationPolicy.isUnsentPlayerMessage(node: reply, canAdvance: true))
        XCTAssertFalse(ChatStoryPresentationPolicy.isUnsentPlayerMessage(node: reply, canAdvance: false))
        XCTAssertEqual(
            ChatStoryPresentationPolicy.manualAdvanceLabel(node: reply, scenarioType: .smallEvent),
            reply.text
        )

        let spacedReply = StoryNode(
            nodeId: "spaced-reply",
            lineOrder: 2,
            speaker: "user",
            messageType: .text,
            text: "そうだね[sp]やってみる"
        )
        XCTAssertEqual(
            ChatStoryPresentationPolicy.manualAdvanceLabel(
                node: spacedReply,
                scenarioType: .smallEvent
            ),
            "そうだね やってみる"
        )
    }

    func testDailyChoiceKeepsRiosQuestionButHidesUnsentPlayerPlaceholder() {
        let question = StoryNode(
            nodeId: "question",
            lineOrder: 1,
            speaker: "character",
            messageType: .choice,
            text: "明日も来れるよね？",
            choiceId: "replies"
        )
        let placeholder = StoryNode(
            nodeId: "placeholder",
            lineOrder: 2,
            speaker: "user",
            messageType: .choice,
            text: "未送信の返信",
            choiceId: "replies"
        )
        let selectedReply = StoryNode(
            nodeId: "selected_reply",
            lineOrder: 2,
            speaker: "user",
            messageType: .text,
            text: "明日も来るよ"
        )
        XCTAssertFalse(ChatStoryPresentationPolicy.isChoicePlaceholder(node: question, scenarioType: .daily))
        XCTAssertTrue(ChatStoryPresentationPolicy.isChoicePlaceholder(node: placeholder, scenarioType: .daily))
        XCTAssertFalse(ChatStoryPresentationPolicy.isChoicePlaceholder(node: selectedReply, scenarioType: .daily))
        XCTAssertFalse(ChatStoryPresentationPolicy.isChoicePlaceholder(node: placeholder, scenarioType: .smallEvent))
    }

    func testLogIsAvailableForPrologueMiddleAndLargeEvents() {
        XCTAssertFalse(StoryLogPresentationPolicy.isAvailable(for: .daily))
        XCTAssertFalse(StoryLogPresentationPolicy.isAvailable(for: .smallEvent))
        XCTAssertTrue(StoryLogPresentationPolicy.isAvailable(for: .prologue))
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
                scenarioType: .prologue,
                hasExplicitTransition: false
            ),
            .adv
        )
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
