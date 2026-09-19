import XCTest
import SwiftUI
@testable import MesugakiRoutine

final class DailyConversationScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testSelectsExactCalendarDateAtAppDayBoundary() throws {
        let septemberFirst = scenario(id: "exact_0901", calendarDate: "2026-09-01")
        let septemberSecond = scenario(id: "exact_0902", calendarDate: "2026-09-02")
        let scenarios = [septemberFirst, septemberSecond]

        XCTAssertEqual(
            DailyConversationSchedule.scenario(
                on: try date(2026, 9, 2, 3, 59),
                from: scenarios,
                calendar: calendar
            )?.scenarioId,
            "exact_0901"
        )
        XCTAssertEqual(
            DailyConversationSchedule.scenario(
                on: try date(2026, 9, 2, 4, 0),
                from: scenarios,
                calendar: calendar
            )?.scenarioId,
            "exact_0902"
        )
    }

    func testSelectsRecurringMonthDayEveryYear() throws {
        let recurring = scenario(id: "christmas", calendarMonthDay: "12-24")

        XCTAssertEqual(
            DailyConversationSchedule.scenario(
                on: try date(2028, 12, 24, 12, 0),
                from: [recurring],
                calendar: calendar
            )?.scenarioId,
            "christmas"
        )
    }

    func testExactCalendarDateOverridesRecurringMonthDay() throws {
        let recurring = scenario(id: "recurring", calendarMonthDay: "09-02")
        let exact = scenario(id: "exact", calendarDate: "2026-09-02")

        XCTAssertEqual(
            DailyConversationSchedule.scenario(
                on: try date(2026, 9, 2, 12, 0),
                from: [recurring, exact],
                calendar: calendar
            )?.scenarioId,
            "exact"
        )
    }

    func testUnscheduledConversationIsNotSelected() throws {
        XCTAssertNil(
            DailyConversationSchedule.scenario(
                on: try date(2026, 9, 2, 12, 0),
                from: [scenario(id: "unscheduled")],
                calendar: calendar
            )
        )
    }

    private func scenario(
        id: String,
        calendarDate: String? = nil,
        calendarMonthDay: String? = nil
    ) -> StoryScenario {
        StoryScenario(
            scenarioId: id,
            scenarioType: .daily,
            calendarDate: calendarDate,
            calendarMonthDay: calendarMonthDay,
            nodes: []
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

final class InteractionCommentSelectorTests: XCTestCase {
    func testSelectsOnlyMatchingTouchTimeAndProfileConditions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        let morning = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 8))
        )
        let comments = [
            InteractionComment(
                id: "eligible",
                text: "eligible",
                condition: "profile:preferredTime=朝型",
                timeCondition: "morning",
                touchArea: "character"
            ),
            InteractionComment(
                id: "wrong_time",
                text: "night",
                timeCondition: "night",
                touchArea: "character"
            ),
            InteractionComment(
                id: "wrong_area",
                text: "head",
                touchArea: "head"
            ),
        ]

        let selected = InteractionCommentSelector.select(
            from: comments,
            touchArea: "character",
            now: morning,
            calendar: calendar,
            profileValues: ["preferredTime": "朝型"],
            randomUnit: { 0 }
        )

        XCTAssertEqual(selected?.id, "eligible")
    }

    func testUsesWeightAndAvoidsImmediateRepeatWhenPossible() {
        let comments = [
            InteractionComment(id: "light", text: "light", weight: 1),
            InteractionComment(id: "heavy", text: "heavy", weight: 3),
        ]

        XCTAssertEqual(
            InteractionCommentSelector.select(
                from: comments,
                touchArea: "character",
                randomUnit: { 0.9 }
            )?.id,
            "heavy"
        )
        XCTAssertEqual(
            InteractionCommentSelector.select(
                from: comments,
                touchArea: "character",
                excluding: "heavy",
                randomUnit: { 0.9 }
            )?.id,
            "light"
        )
    }
}
