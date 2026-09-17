import XCTest
import SwiftUI
@testable import MesugakiRoutine

final class DailyConversationScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testConversationAdvancesAtAppDayBoundary() throws {
        let anchor = try date(2026, 9, 1, 4, 0)

        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 2, 3, 59),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            0
        )
        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 2, 4, 0),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            1
        )
    }

    func testConversationWrapsAfterAvailableScenarios() throws {
        let anchor = try date(2026, 9, 1, 4, 0)
        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 15, 4, 0),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            0
        )
    }

    func testEmptyCatalogHasNoSelection() throws {
        XCTAssertNil(
            DailyConversationSchedule.scenarioIndex(
                anchorDate: try date(2026, 9, 1, 4, 0),
                scenarioCount: 0,
                calendar: calendar
            )
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}

@MainActor
final class InteractionHomeCardRenderingTests: XCTestCase {
    func testLowerArtworkBlurKeepsUpperSixtyPercentSharpAndOpaque() throws {
        let pattern = Canvas { context, size in
            for x in stride(from: CGFloat.zero, to: size.width, by: 8) {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 4, height: size.height)), with: .color(.black)
                )
            }
        }
        .background(.white)
        .frame(width: 180, height: 100)
        let sharp = try XCTUnwrap(ImageRenderer(content: pattern).uiImage)
        let blurred = try XCTUnwrap(ImageRenderer(
            content: pattern.modifier(InteractionArtworkBottomBlur())
        ).uiImage)
        XCTAssertEqual(sharp.size, blurred.size)
        let upperSharp = try artworkPixel(sharp, x: 22, y: 20)
        let upperBlurred = try artworkPixel(blurred, x: 22, y: 20)
        for channel in 0..<4 {
            XCTAssertEqual(Int(upperSharp[channel]), Int(upperBlurred[channel]), accuracy: 2)
        }
        let lowerSharp = try artworkPixel(sharp, x: 22, y: 85)
        let lowerBlurred = try artworkPixel(blurred, x: 22, y: 85)
        XCTAssertGreaterThan(abs(Int(lowerSharp[0]) - Int(lowerBlurred[0])), 20)
        for y in [20, 65, 85] {
            XCTAssertGreaterThanOrEqual(Int(try artworkPixel(blurred, x: 22, y: y)[3]), 250)
        }
        let attachment = XCTAttachment(image: blurred)
        attachment.name = "Lower 40 percent artwork blur"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func artworkPixel(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }

    func testTodayCardDoesNotFadeWhenConversationIsUnavailable() throws {
        var samples: [[UInt8]] = []
        for isAvailable in [true, false] {
            let content = TodayConversationCard(
                title: "今日の会話", isUnread: false, hasResumePosition: false,
                isAvailable: isAvailable, action: {}
            )
            .frame(width: 180)
            .background(AppColor.secondary)
            .environment(\.colorScheme, .light)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Today card available=\(isAvailable)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: URL(fileURLWithPath: "/tmp/zako_today_card_\(isAvailable).png"))

            // 名前・セリフ・立ち絵のない背景部分で、カード全体の濃さを比較する。
            let cgImage = try XCTUnwrap(image.cgImage)
            let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 162, y: 60, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            samples.append(rgba)
        }
        for channel in 0..<4 {
            XCTAssertEqual(Int(samples[0][channel]), Int(samples[1][channel]), accuracy: 2)
        }
    }

    func testCardsAndLabeledSpeechRenderAtNarrowAndRegularWidths() throws {
        for width: CGFloat in [320, 390] {
            let content = VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    InteractionProgressMiniCard(progress: .init(
                        chapterTitle: "第1章", completedCount: 5, totalCount: 7,
                        nextStoryText: "次のストーリーまで あと2日"
                    ))
                }
                InteractionCharacterSpeechBubble(
                    text: "がんばってね、ざこざこおにいさん♡", speakerName: "莉央"
                )
                InteractionHomeCardGrid {
                    TodayConversationCard(
                        title: "今日の会話", isUnread: true, hasResumePosition: false,
                        isAvailable: true, action: {}
                    )
                    InteractionHomeFeatureCard(
                        kind: .story, title: "ストーリー", detail: "莉央との物語を読む"
                    )
                    InteractionHomeFeatureCard(
                        kind: .memories, title: "思い出", detail: "あの時の莉央に会いに"
                    )
                    InteractionHomeFeatureCard(kind: .freeTalk, title: "ふりーとーく", detail: "")
                }
            }
            .padding(16)
            .frame(width: width)
            .background(AppColor.background)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width, accuracy: 0.5)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Interaction cards \(Int(width))pt"
            attachment.lifetime = .keepAlways
            add(attachment)
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: URL(fileURLWithPath: "/tmp/zakozako_interaction_cards_\(Int(width)).png"))
        }
    }

    func testFourCardGridKeepsTheSameHeightWhenTodayIsReadOrUnavailable() throws {
        let states: [(unread: Bool, available: Bool)] = [(true, true), (false, true), (false, false)]
        for width: CGFloat in [320, 390] {
            for state in states {
                let content = InteractionHomeCardGrid {
                    TodayConversationCard(
                        title: "今日の会話", isUnread: state.unread, hasResumePosition: false,
                        isAvailable: state.available, action: {}
                    )
                    InteractionHomeFeatureCard(
                        kind: .story, title: "ストーリー", detail: "莉央との物語を読む"
                    )
                    InteractionHomeFeatureCard(
                        kind: .memories, title: "思い出", detail: "あの時の莉央に会いに"
                    )
                    InteractionHomeFeatureCard(kind: .freeTalk, title: "ふりーとーく", detail: "")
                }
                .frame(width: width)
                let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                XCTAssertEqual(image.size.width, width, accuracy: 0.5)
                XCTAssertEqual(image.size.height, 130 * 2 + 12, accuracy: 0.5)
            }
        }
    }
}
