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
