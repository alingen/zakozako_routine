import SwiftUI
import XCTest
@testable import MesugakiRoutine

@MainActor
final class FullscreenNarrationRenderingTests: XCTestCase {
    func testOrdinaryNarrationAppearsInlineAndWaitsForNextButton() async throws {
        let preceding = StoryNode(nodeId: "rio", lineOrder: 1, speaker: "rio", messageType: .text,
                                  text: "まあ", speakerName: "莉央", screenMode: .chat)
        let narration = StoryNode(nodeId: "inline", lineOrder: 2, speaker: "narrator", messageType: .text,
                                  text: "数秒、返信が来ない。[br]ノートを力ずくで取り返したって、負けたままだ。",
                                  screenMode: .chat, uiVariant: .narration)
        let presented = expectation(description: "Inline narration appears after a pause")
        var advances = 0
        let view = ChatStoryRenderer(
            node: narration, scenarioType: .middleEvent, visibleNodes: [preceding, narration],
            onAdvance: { advances += 1 }, onPresentNode: { presented.fulfill() },
            onSelectChoice: { _ in }, onDismissModal: {}
        )
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [presented], timeout: 3)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(advances, 0)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "inline-chat-narration-compact"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNarrationRevealsWithoutAutomaticAdvanceOnCompactIPhone() async throws {
        let history = [
            StoryNode(nodeId: "chat1", lineOrder: 1, speaker: "user", messageType: .text, text: "走ったよ", screenMode: .chat),
            StoryNode(nodeId: "chat2", lineOrder: 2, speaker: "rio", messageType: .text, text: "何分？", screenMode: .chat),
            StoryNode(nodeId: "chat3", lineOrder: 3, speaker: "user", messageType: .text, text: "10分", screenMode: .chat),
            StoryNode(nodeId: "chat4", lineOrder: 4, speaker: "rio", messageType: .text, text: "ざこざこおにいさん♡", screenMode: .chat),
        ]
        let node = StoryNode(nodeId: "narration", lineOrder: 5, speaker: "narrator", messageType: .text,
                             text: "莉央との最初の約束だった。", screenMode: .chat, uiVariant: .fullscreenNarration)
        let presented = expectation(description: "Narration appears after controls fade")
        var advances = 0
        let view = StoryPlayerView(
            input: StoryPlayerViewSnapshot(title: "最初の約束", scenarioType: .middleEvent,
                                           currentNode: node, currentMode: .chat, visibleChatNodes: history + [node]),
            onAdvance: { _ in advances += 1 }, onChoice: { _ in }, onDismissModal: {},
            onPresentNode: { presented.fulfill() }, onSkip: {}, onClose: {}
        )
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .light))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [presented], timeout: 3)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(advances, 0, "Only a reader tap should advance narration")
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "fullscreen-chat-narration-compact"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class StoryProtagonistDisplayNameTests: XCTestCase {
    private func node(speakerName: String?) -> StoryNode {
        StoryNode(
            nodeId: "name", lineOrder: 1, speaker: "protagonist", messageType: .text,
            speakerName: speakerName
        )
    }

    func testKeepsAccountNameWhenReplacingProtagonistPlaceholder() {
        XCTAssertEqual(
            node(speakerName: "主人公（孤高@考察垢）").protagonistDisplayName(userName: "たけし"),
            "たけし（孤高@考察垢）"
        )
    }

    func testOrdinaryDialogueStillUsesOnlyConfiguredName() {
        for speakerName: String? in [nil, "", "主人公", "protagonist"] {
            XCTAssertEqual(node(speakerName: speakerName).protagonistDisplayName(userName: "たけし"), "たけし")
        }
    }

    func testEmptyNicknameFallsBackToProtagonistWithSuffix() {
        XCTAssertEqual(
            node(speakerName: "主人公（孤高@考察垢）").protagonistDisplayName(userName: " \n"),
            "主人公（孤高@考察垢）"
        )
    }

    func testTrimsOuterWhitespaceAndPreservesOtherAccountNames() {
        XCTAssertEqual(
            node(speakerName: " 主人公（別アカウント） ").protagonistDisplayName(userName: " たけし "),
            "たけし（別アカウント）"
        )
        XCTAssertEqual(
            node(speakerName: "主人公(孤高@考察垢)").protagonistDisplayName(userName: "たけし"),
            "たけし(孤高@考察垢)"
        )
    }

    func testDoesNotAppendUnrelatedSpeakerNamesOrRepeatNickname() {
        for speakerName in ["別人（孤高@考察垢）", "主人公の友人", "たけし（孤高@考察垢）"] {
            XCTAssertEqual(node(speakerName: speakerName).protagonistDisplayName(userName: "たけし"), "たけし")
        }
        XCTAssertEqual(
            node(speakerName: "主人公（孤高@考察垢）").protagonistDisplayName(userName: "主人公たけし"),
            "主人公たけし（孤高@考察垢）"
        )
    }
}

final class StorySceneChangeCommandTests: XCTestCase {
    func testScreenModeSupportsBothArgumentNamesAndRowFallback() {
        let arguments: [JSONValue?] = [
            .object(["screen_mode": .string("chat")]),
            .object(["screen": .string("chat")]),
            nil,
        ]
        for args in arguments {
            let node = StoryNode(
                nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
                screenMode: .chat, command: "scene_change", commandArgs: args
            )
            let result = StoryCommandDispatcher().dispatch(node: node)
            XCTAssertEqual(result.effects, [.setScreenMode(.chat)])
            XCTAssertNil(result.diagnostic)
        }
    }

    func testExplicitArgumentsTakePrecedenceOverAliasesAndRowMode() {
        let node = StoryNode(
            nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
            screenMode: .adv, command: "scene_change",
            commandArgs: .object([
                "screen_mode": .string("chat"), "screen": .string("call"),
            ])
        )
        XCTAssertEqual(StoryCommandDispatcher().dispatch(node: node).effects, [.setScreenMode(.chat)])
    }

    func testScreenAliasWorksWithoutRowMode() {
        let node = StoryNode(
            nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
            command: "scene_change", commandArgs: .object(["screen": .string("chat")])
        )
        let result = StoryCommandDispatcher().dispatch(node: node)
        XCTAssertEqual(result.effects, [.setScreenMode(.chat)])
        XCTAssertNil(result.diagnostic)
    }

    func testMissingBackgroundAndScreenStillReportsDiagnostic() {
        let node = StoryNode(
            nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
            command: "scene_change"
        )
        let result = StoryCommandDispatcher().dispatch(node: node)
        XCTAssertTrue(result.effects.isEmpty)
        XCTAssertEqual(result.diagnostic, "command scene_change にbackground / screen_modeがありません")
    }
}

final class StorySoundEffectCommandTests: XCTestCase {
    func testPlaySEUsesAssetIDAndClampsVolume() {
        let node = StoryNode(
            nodeId: "sound",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            command: "play_se",
            commandArgs: .object([
                "asset_id": .string("se_defeat"),
                "volume": .number(1.5),
            ])
        )

        XCTAssertEqual(
            StoryCommandDispatcher().dispatch(node: node).effects,
            [.playSoundEffect(StorySoundEffectPlayback(assetID: "se_defeat", volume: 1))]
        )
    }

    func testPlaySERequiresAnAssetID() {
        let node = StoryNode(
            nodeId: "missing_sound",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            command: "play_se"
        )

        let result = StoryCommandDispatcher().dispatch(node: node)
        XCTAssertTrue(result.effects.isEmpty)
        XCTAssertNotNil(result.diagnostic)
    }

    func testPlaySESupportsLoopingAndStoppingTheSameAsset() {
        let playNode = StoryNode(
            nodeId: "loop_sound",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            command: "play_se",
            commandArgs: .object([
                "action": .string("play"),
                "asset_id": .string("se_keyboard_typing"),
                "loop": .bool(true),
                "volume": .number(0.6),
            ])
        )
        let stopNode = StoryNode(
            nodeId: "stop_sound",
            lineOrder: 2,
            speaker: "system",
            messageType: .action,
            command: "play_se",
            commandArgs: .object([
                "action": .string("stop"),
                "asset_id": .string("se_keyboard_typing"),
            ])
        )

        XCTAssertEqual(
            StoryCommandDispatcher().dispatch(node: playNode).effects,
            [
                .playSoundEffect(
                    StorySoundEffectPlayback(
                        assetID: "se_keyboard_typing",
                        volume: 0.6,
                        loop: true
                    )
                ),
            ]
        )
        XCTAssertEqual(
            StoryCommandDispatcher().dispatch(node: stopNode).effects,
            [.stopSoundEffect("se_keyboard_typing")]
        )
    }
}

final class StoryPortraitHesitationCommandTests: XCTestCase {
    func testDefaultDurationIsFifteenHundredMilliseconds() {
        let node = StoryNode(
            nodeId: "hesitate-default",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            command: "portrait_hesitate"
        )

        XCTAssertEqual(
            StoryCommandDispatcher().dispatch(node: node).effects,
            [.portraitHesitation(milliseconds: 1_500)]
        )
    }

    func testExplicitDurationIsUsedAndCapped() {
        let node = StoryNode(
            nodeId: "hesitate-override",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            command: "portrait_hesitate",
            commandArgs: .object(["duration_ms": .number(1_800)])
        )
        let oversized = StoryNode(
            nodeId: "hesitate-capped",
            lineOrder: 2,
            speaker: "system",
            messageType: .action,
            command: "portrait_hesitate",
            commandArgs: .object(["duration_ms": .number(9_000)])
        )

        XCTAssertEqual(
            StoryCommandDispatcher().dispatch(node: node).effects,
            [.portraitHesitation(milliseconds: 1_800)]
        )
        let capped = StoryCommandDispatcher().dispatch(node: oversized)
        XCTAssertEqual(capped.effects, [.portraitHesitation(milliseconds: 5_000)])
        XCTAssertNotNil(capped.diagnostic)
    }
}

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
    func testHesitationCommandNeverShowsDialogueWindow() {
        let node = StoryNode(
            nodeId: "hesitation-no-window",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            text: "",
            screenMode: .adv,
            uiVariant: .dialogue,
            command: "portrait_hesitate"
        )

        XCTAssertFalse(ADVTextWindowPresentationPolicy.showsContent(for: node))
    }

    func testHesitationBubbleAnimationShowsDotsInSequence() {
        XCTAssertEqual(ADVHesitationBubbleAnimation.visibleDotCount(elapsed: 0, reduceMotion: false), 1)
        XCTAssertEqual(ADVHesitationBubbleAnimation.visibleDotCount(elapsed: 0.4, reduceMotion: false), 2)
        XCTAssertEqual(ADVHesitationBubbleAnimation.visibleDotCount(elapsed: 0.8, reduceMotion: false), 3)
        XCTAssertEqual(ADVHesitationBubbleAnimation.visibleDotCount(elapsed: 1.1, reduceMotion: false), 1)
        XCTAssertEqual(ADVHesitationBubbleAnimation.visibleDotCount(elapsed: 0, reduceMotion: true), 3)
    }

    func testHesitationBubbleOverlaysPortraitWithoutChangingSceneLayout() throws {
        let node = StoryNode(
            nodeId: "hesitation-layout",
            lineOrder: 1,
            speaker: "rio",
            messageType: .action,
            text: "",
            screenMode: .adv,
            uiVariant: .sceneTransition
        )

        func render(
            size: CGSize,
            portraitAssetID: String?,
            cgAssetID: String? = nil,
            showsBubble: Bool
        ) throws -> CGImage {
            let content = ADVStoryRenderer(
                node: node,
                scenarioType: .prologue,
                backgroundAssetID: "bg_protagonist_living_room",
                portraitAssetID: portraitAssetID,
                cgAssetID: cgAssetID,
                showsHesitationBubble: showsBubble,
                showsPlaybackControls: false,
                onAdvance: { _ in },
                onSelectChoice: { _ in },
                onDismissModal: {}
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage?.cgImage)
        }

        func rgba(in image: CGImage, x: Int, y: Int) throws -> [UInt8] {
            let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            var result = [UInt8](repeating: 0, count: 4)
            try result.withUnsafeMutableBytes { bytes in
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
            return result
        }

        for size in [
            CGSize(width: 320, height: 568),
            CGSize(width: 390, height: 844),
            CGSize(width: 428, height: 926)
        ] {
            let withoutBubble = try render(
                size: size,
                portraitAssetID: "portrait_rio_neutral",
                showsBubble: false
            )
            let withBubble = try render(
                size: size,
                portraitAssetID: "portrait_rio_neutral",
                showsBubble: true
            )
            XCTAssertEqual(withBubble.width, Int(size.width))
            XCTAssertEqual(withBubble.height, Int(size.height))
            XCTAssertEqual(
                try rgba(in: withBubble, x: 2, y: 40),
                try rgba(in: withoutBubble, x: 2, y: 40),
                "The bubble must not move the background at width \(size.width)."
            )

            let bubbleX = Int(size.width * 0.76)
            let bubbleY = Int(size.height * 0.25 - 16)
            let bubblePixel = try rgba(in: withBubble, x: bubbleX, y: bubbleY)
            XCTAssertNotEqual(
                bubblePixel,
                try rgba(in: withoutBubble, x: bubbleX, y: bubbleY)
            )
            XCTAssertGreaterThan(bubblePixel[0], 230)
            XCTAssertGreaterThan(bubblePixel[1], 230)
            XCTAssertGreaterThan(bubblePixel[2], 230)

            let noPortrait = try render(
                size: size,
                portraitAssetID: nil,
                showsBubble: true
            )
            let noPortraitBaseline = try render(
                size: size,
                portraitAssetID: nil,
                showsBubble: false
            )
            XCTAssertEqual(
                try rgba(in: noPortrait, x: bubbleX, y: bubbleY),
                try rgba(in: noPortraitBaseline, x: bubbleX, y: bubbleY)
            )

            let withCG = try render(
                size: size,
                portraitAssetID: "portrait_rio_neutral",
                cgAssetID: "cg_test",
                showsBubble: true
            )
            let withCGBaseline = try render(
                size: size,
                portraitAssetID: "portrait_rio_neutral",
                cgAssetID: "cg_test",
                showsBubble: false
            )
            XCTAssertEqual(
                try rgba(in: withCG, x: bubbleX, y: bubbleY),
                try rgba(in: withCGBaseline, x: bubbleX, y: bubbleY)
            )
        }
    }

    func testEmptyWaitTransitionKeepsBlackoutFreeOfDialogueBox() throws {
        let waitNode = StoryNode(
            nodeId: "blackout_wait",
            lineOrder: 1,
            speaker: "system",
            messageType: .action,
            text: "",
            screenMode: .adv,
            uiVariant: .sceneTransition,
            command: "wait",
            commandArgs: .object(["duration_ms": .number(300)])
        )
        let labelledNode = StoryNode(
            nodeId: "labelled_transition",
            lineOrder: 2,
            speaker: "narrator",
            messageType: .text,
            text: "数週間前。",
            screenMode: .adv,
            uiVariant: .sceneTransition
        )

        XCTAssertFalse(ADVTextWindowPresentationPolicy.showsContent(for: waitNode))
        XCTAssertTrue(ADVTextWindowPresentationPolicy.showsContent(for: labelledNode))

        func sampledRed(for node: StoryNode) throws -> UInt8 {
            let content = ADVStoryRenderer(
                node: node,
                scenarioType: .prologue,
                showsPlaybackControls: false,
                onAdvance: { _ in },
                onSelectChoice: { _ in },
                onDismissModal: {}
            )
            .frame(width: 320, height: 568)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage?.cgImage)
            let sample = try XCTUnwrap(
                image.cropping(to: CGRect(x: 160, y: 450, width: 1, height: 1))
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
            return rgba[0]
        }

        XCTAssertLessThanOrEqual(try sampledRed(for: waitNode), 2)
        XCTAssertGreaterThan(try sampledRed(for: labelledNode), 100)
    }

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

    func testEventPlayerLineUsesPrefilledComposerButDailyKeepsReplyButton() {
        let reply = StoryNode(
            nodeId: "reply", lineOrder: 1, speaker: "user", messageType: .text, text: "10分"
        )
        for scenarioType: StoryScenarioType in [.prologue, .smallEvent, .middleEvent, .largeEvent] {
            XCTAssertTrue(ChatStoryPresentationPolicy.usesPrefilledComposer(
                node: reply, scenarioType: scenarioType
            ))
        }
        XCTAssertFalse(ChatStoryPresentationPolicy.usesPrefilledComposer(
            node: reply, scenarioType: .daily
        ))

        let emptyReply = StoryNode(
            nodeId: "empty-reply", lineOrder: 2, speaker: "user", messageType: .text, text: ""
        )
        XCTAssertFalse(ChatStoryPresentationPolicy.usesPrefilledComposer(
            node: emptyReply, scenarioType: .middleEvent
        ))

        let rio = StoryNode(
            nodeId: "rio", lineOrder: 3, speaker: "rio", messageType: .text, text: "何分？"
        )
        XCTAssertFalse(ChatStoryPresentationPolicy.usesPrefilledComposer(
            node: rio, scenarioType: .middleEvent
        ))
    }

    func testTerminalEventChatButtonSaysCloseWithoutChangingIntermediateOrReplyLabels() {
        let narration = StoryNode(
            nodeId: "final", lineOrder: 1, speaker: "narrator", messageType: .text,
            text: "莉央との最初の約束だった。", screenMode: .chat, uiVariant: .narration
        )
        for scenarioType: StoryScenarioType in [.prologue, .middleEvent, .largeEvent] {
            XCTAssertEqual(ChatStoryPresentationPolicy.manualAdvanceLabel(
                node: narration, scenarioType: scenarioType, isTerminalNode: true
            ), "閉じる")
            XCTAssertEqual(ChatStoryPresentationPolicy.manualAdvanceLabel(
                node: narration, scenarioType: scenarioType
            ), "次へ")
        }
        let reply = StoryNode(
            nodeId: "reply", lineOrder: 1, speaker: "user", messageType: .text, text: "また明日"
        )
        XCTAssertEqual(ChatStoryPresentationPolicy.manualAdvanceLabel(
            node: reply, scenarioType: .middleEvent, isTerminalNode: true
        ), "また明日")
        XCTAssertEqual(ChatStoryPresentationPolicy.manualAdvanceLabel(
            node: reply, scenarioType: .daily, isTerminalNode: true
        ), "返信する")
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

    func testChatNarrationUsesInlineSeparatorAndRemainsInHistory() {
        let narration = StoryNode(
            nodeId: "narration",
            lineOrder: 1,
            speaker: "narrator",
            messageType: .text,
            text: "少しして。",
            screenMode: .chat,
            uiVariant: .narration
        )

        XCTAssertTrue(EventChatSystemPresentationPolicy.usesInlineNarration(node: narration))
        for type: StoryScenarioType in [.prologue, .middleEvent, .largeEvent, .smallEvent, .daily] {
            XCTAssertFalse(EventChatSystemPresentationPolicy.omitsFromChatHistory(node: narration, scenarioType: type))
        }
        let dialogue = StoryNode(nodeId: "rio", lineOrder: 2, speaker: "rio", messageType: .text,
                                 text: "まあ", screenMode: .chat, uiVariant: .dialogue)
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesInlineNarration(node: dialogue))
    }

    func testChatMonologueIsSeparatedFromSceneTransitionDivider() {
        let monologue = StoryNode(
            nodeId: "monologue", lineOrder: 1, speaker: "narrator", messageType: .text,
            text: "即答。想定済みだ。", screenMode: .chat, uiVariant: .narration
        )
        XCTAssertTrue(EventChatSystemPresentationPolicy.usesInlineMonologue(node: monologue))

        let untaggedNarrator = StoryNode(
            nodeId: "untagged", lineOrder: 2, speaker: "narrator", messageType: .text,
            text: "こいつ…", screenMode: .chat
        )
        XCTAssertTrue(EventChatSystemPresentationPolicy.usesInlineMonologue(node: untaggedNarrator))

        let transition = StoryNode(
            nodeId: "transition", lineOrder: 3, speaker: "system", messageType: .text,
            text: "翌日", screenMode: .chat, uiVariant: .sceneTransition
        )
        XCTAssertTrue(EventChatSystemPresentationPolicy.usesInlineNarration(node: transition))
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesInlineMonologue(node: transition))

        let systemLine = StoryNode(
            nodeId: "system", lineOrder: 4, speaker: "system", messageType: .text,
            text: "end", screenMode: .chat
        )
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesInlineMonologue(node: systemLine))

        let fullscreen = StoryNode(
            nodeId: "fullscreen", lineOrder: 5, speaker: "narrator", messageType: .text,
            text: "代わりに、白紙は少し減った。", screenMode: .chat, uiVariant: .fullscreenNarration
        )
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesInlineMonologue(node: fullscreen))
    }

    func testEventChatNarrationWaitsForTapInsteadOfAutomaticallyAdvancing() {
        for speaker in ["narrator", "system"] {
            let node = StoryNode(
                nodeId: "narration", lineOrder: 1, speaker: speaker,
                messageType: .text, text: "それが。", screenMode: .chat,
                uiVariant: .narration
            )
            for scenarioType: StoryScenarioType in [.prologue, .middleEvent, .largeEvent] {
                let renderer = ChatStoryRenderer(
                    node: node, scenarioType: scenarioType,
                    onAdvance: {}, onPresentNode: {}, onSelectChoice: { _ in }, onDismissModal: {}
                )
                XCTAssertFalse(renderer.shouldAutoAdvance)
                XCTAssertTrue(EventChatSystemPresentationPolicy.requiresManualAdvance(
                    node: node, scenarioType: scenarioType
                ))
            }
            let smallEvent = ChatStoryRenderer(
                node: node, scenarioType: .smallEvent,
                onAdvance: {}, onPresentNode: {}, onSelectChoice: { _ in }, onDismissModal: {}
            )
            XCTAssertTrue(smallEvent.shouldAutoAdvance, "Small-event separators retain automatic progression")
        }
    }

    func testFullscreenNarrationIsOptInManualAndExcludedFromChatBubbles() throws {
        let node = StoryNode(
            nodeId: "fullscreen", lineOrder: 1, speaker: "narrator", messageType: .text,
            text: "それが。[br]莉央との最初の約束だった。", screenMode: .chat,
            uiVariant: .fullscreenNarration
        )
        let decoded = try JSONDecoder().decode(StoryNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(decoded.uiVariant, .fullscreenNarration)
        XCTAssertEqual(decoded.uiVariant?.rawValue, "fullscreen_narration")
        XCTAssertEqual(decoded.storyDisplayText, "それが。\n莉央との最初の約束だった。")
        XCTAssertTrue(EventChatSystemPresentationPolicy.usesFullscreenNarration(node: decoded))
        for type: StoryScenarioType in [.prologue, .middleEvent, .largeEvent, .smallEvent, .daily] {
            XCTAssertFalse(EventChatSystemPresentationPolicy.usesInlineNarration(node: node))
            XCTAssertTrue(EventChatSystemPresentationPolicy.omitsFromChatHistory(node: node, scenarioType: type))
            for terminal in [false, true] {
                let renderer = ChatStoryRenderer(
                    node: node, scenarioType: type, isTerminalNode: terminal,
                    onAdvance: {}, onPresentNode: {}, onSelectChoice: { _ in }, onDismissModal: {}
                )
                XCTAssertFalse(renderer.shouldAutoAdvance)
            }
        }
        let ordinary = StoryNode(
            nodeId: "ordinary", lineOrder: 2, speaker: "narrator", messageType: .text,
            text: "数分後", screenMode: .chat, uiVariant: .narration
        )
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesFullscreenNarration(node: ordinary))
        XCTAssertTrue(EventChatSystemPresentationPolicy.usesInlineNarration(node: ordinary))
        let empty = StoryNode(
            nodeId: "empty", lineOrder: 3, speaker: "system", messageType: .action,
            screenMode: .chat, uiVariant: .fullscreenNarration
        )
        XCTAssertFalse(EventChatSystemPresentationPolicy.usesFullscreenNarration(node: empty))
    }

    func testFinalInlineNarrationWaitsForCloseButton() {
        let node = StoryNode(
            nodeId: "final", lineOrder: 2, speaker: "narrator", messageType: .text,
            text: "莉央との最初の約束だった。", screenMode: .chat, uiVariant: .narration
        )
        XCTAssertTrue(EventChatSystemPresentationPolicy.requiresManualAdvance(
            node: node, scenarioType: .middleEvent
        ))
        XCTAssertEqual(ChatStoryPresentationPolicy.manualAdvanceLabel(
            node: node, scenarioType: .middleEvent, isTerminalNode: true
        ), "閉じる")
        let renderer = ChatStoryRenderer(
            node: node, scenarioType: .middleEvent, isTerminalNode: true,
            onAdvance: {}, onPresentNode: {}, onSelectChoice: { _ in }, onDismissModal: {}
        )
        XCTAssertFalse(renderer.shouldAutoAdvance)
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
