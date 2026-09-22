import XCTest
import SwiftUI
import SwiftData
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

    func testLegacyScenarioWithoutCatalogMetadataDefaultsToEnabled() throws {
        let json =
            """
            {
              "scenarioId": "legacy_daily",
              "scenarioType": "daily",
              "calendarMonthDay": "09-02",
              "nodes": []
            }
            """

        let decoded = try JSONDecoder().decode(StoryScenario.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.enabled)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.displayOrder)
        XCTAssertNil(decoded.category)
        XCTAssertNil(decoded.status)
    }

    func testDecodesDailyCatalogMetadata() throws {
        let json =
            """
            {
              "scenarioId": "daily_catalog_entry",
              "scenarioType": "daily",
              "title": "一人映画",
              "displayOrder": 3,
              "category": "質問系",
              "calendarDate": "2026-09-16",
              "status": "公開可能",
              "enabled": false,
              "nodes": []
            }
            """

        let decoded = try JSONDecoder().decode(StoryScenario.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.title, "一人映画")
        XCTAssertEqual(decoded.displayOrder, 3)
        XCTAssertEqual(decoded.category, "質問系")
        XCTAssertEqual(decoded.calendarDate, "2026-09-16")
        XCTAssertEqual(decoded.status, "公開可能")
        XCTAssertFalse(decoded.enabled)
    }

    func testRepositoryFiltersDisabledDailyAndUsesCatalogDisplayOrder() throws {
        let repository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [
                    scenario(id: "daily_without_order"),
                    scenario(id: "daily_second", displayOrder: 2),
                    scenario(id: "daily_first_b", displayOrder: 1),
                    scenario(id: "daily_disabled", displayOrder: 0, enabled: false),
                    scenario(id: "daily_first_a", displayOrder: 1),
                    StoryScenario(
                        scenarioId: "event_scenario",
                        scenarioType: .smallEvent,
                        displayOrder: 0,
                        nodes: []
                    ),
                ],
                choiceGroups: [],
                events: []
            )
        )

        XCTAssertEqual(
            repository.dailyScenarios.map(\.scenarioId),
            ["daily_first_a", "daily_first_b", "daily_second", "daily_without_order"]
        )
    }

    private func scenario(
        id: String,
        displayOrder: Int? = nil,
        calendarDate: String? = nil,
        calendarMonthDay: String? = nil,
        enabled: Bool = true
    ) -> StoryScenario {
        StoryScenario(
            scenarioId: id,
            scenarioType: .daily,
            displayOrder: displayOrder,
            calendarDate: calendarDate,
            calendarMonthDay: calendarMonthDay,
            enabled: enabled,
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
final class InteractionViewModelOnboardingConversationTests: XCTestCase {
    private var container: ModelContainer?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testScheduledConversationHasPriorityAndKeepsNormalDailyPlaybackKey() throws {
        let now = try date(2026, 9, 20, 12, 0)
        let launch = InteractionViewModel.onboardingConversationLaunch(
            now: now,
            calendar: calendar,
            dailyScenarios: [
                scenario(id: "daily_001"),
                scenario(id: "scheduled", calendarDate: "2026-09-20"),
            ],
            checkpointForPlaybackKey: { _ in
                XCTFail("Scheduled conversations must not consult the onboarding checkpoint")
                return nil
            }
        )

        XCTAssertEqual(launch?.scenario.scenarioId, "scheduled")
        XCTAssertEqual(launch?.playbackKey, "daily:2026-09-20")
    }

    func testUnscheduledDaily001UsesStableDedicatedKeyAcrossDates() throws {
        let scenarios = [scenario(id: "daily_002"), scenario(id: "daily_001")]
        let first = InteractionViewModel.onboardingConversationLaunch(
            now: try date(2026, 9, 20, 12, 0),
            calendar: calendar,
            dailyScenarios: scenarios,
            checkpointForPlaybackKey: { _ in nil }
        )
        let nextDay = InteractionViewModel.onboardingConversationLaunch(
            now: try date(2026, 9, 21, 12, 0),
            calendar: calendar,
            dailyScenarios: scenarios,
            checkpointForPlaybackKey: { _ in nil }
        )

        XCTAssertEqual(first?.scenario.scenarioId, "daily_001")
        XCTAssertEqual(first?.playbackKey, "daily:onboarding:daily_001")
        XCTAssertEqual(nextDay?.playbackKey, first?.playbackKey)
    }

    func testMissingDaily001UsesFirstUnscheduledDailyScenario() throws {
        let launch = InteractionViewModel.onboardingConversationLaunch(
            now: try date(2026, 9, 20, 12, 0),
            calendar: calendar,
            dailyScenarios: [
                scenario(id: "another-date", calendarDate: "2026-10-01"),
                scenario(id: "daily_010"),
                scenario(id: "daily_011"),
            ],
            checkpointForPlaybackKey: { _ in nil }
        )

        XCTAssertEqual(launch?.scenario.scenarioId, "daily_010")
        XCTAssertEqual(launch?.playbackKey, "daily:onboarding:daily_010")
    }

    func testCompletedOnboardingConversationIsNotOpenedAgain() throws {
        let playbackKey = "daily:onboarding:daily_001"
        let completed = StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: "daily_001",
            isCompleted: true,
            updatedAt: try date(2026, 9, 19, 12, 0)
        )

        let launch = InteractionViewModel.onboardingConversationLaunch(
            now: try date(2026, 9, 20, 12, 0),
            calendar: calendar,
            dailyScenarios: [scenario(id: "daily_001")],
            checkpointForPlaybackKey: { key in
                key == playbackKey ? completed : nil
            }
        )

        XCTAssertNil(launch)
    }

    func testIncompleteOnboardingConversationCanResume() throws {
        let playbackKey = "daily:onboarding:daily_001"
        let incomplete = StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: "daily_001",
            currentNodeId: "daily_001_02",
            visitedNodeIds: ["daily_001_01"],
            isCompleted: false,
            updatedAt: try date(2026, 9, 19, 12, 0)
        )

        let launch = InteractionViewModel.onboardingConversationLaunch(
            now: try date(2026, 9, 20, 12, 0),
            calendar: calendar,
            dailyScenarios: [scenario(id: "daily_001")],
            checkpointForPlaybackKey: { key in
                key == playbackKey ? incomplete : nil
            }
        )

        XCTAssertEqual(launch?.scenario.scenarioId, "daily_001")
        XCTAssertEqual(launch?.playbackKey, playbackKey)
    }

    func testPersistedIdentityKeepsOriginalScheduledConversationAcrossDates() throws {
        let original = scenario(id: "original", calendarDate: "2026-09-20")
        let nextDay = scenario(id: "next-day", calendarDate: "2026-09-21")
        let initialLaunch = try XCTUnwrap(
            InteractionViewModel.onboardingConversationLaunch(
                now: try date(2026, 9, 20, 12, 0),
                calendar: calendar,
                dailyScenarios: [original, nextDay],
                checkpointForPlaybackKey: { _ in nil }
            )
        )
        let identity = InteractionViewModel.onboardingConversationIdentity(for: initialLaunch)

        let resumed = InteractionViewModel.onboardingConversationLaunch(
            identity: identity,
            dailyScenarios: [original, nextDay],
            checkpointForPlaybackKey: { _ in nil }
        )

        XCTAssertEqual(resumed?.scenario.scenarioId, "original")
        XCTAssertEqual(resumed?.playbackKey, "daily:2026-09-20")
    }

    func testPersistedIdentityIsNotOfferedAfterConversationCompletes() throws {
        let identity = OnboardingConversationIdentity(
            scenarioID: "daily_001",
            playbackKey: "daily:onboarding:daily_001"
        )
        let completed = StoryPlaybackCheckpoint(
            playbackKey: identity.playbackKey,
            scenarioId: identity.scenarioID,
            isCompleted: true,
            updatedAt: try date(2026, 9, 20, 12, 0)
        )

        let resumed = InteractionViewModel.onboardingConversationLaunch(
            identity: identity,
            dailyScenarios: [scenario(id: "daily_001")],
            checkpointForPlaybackKey: { _ in completed }
        )

        XCTAssertNil(resumed)
    }

    func testDeferredConversationCanBeOpenedFromTheNormalTodayCard() throws {
        let schema = Schema([
            Routine.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let now = try date(2099, 10, 2, 12, 0)
        let viewModel = InteractionViewModel()

        viewModel.configure(context: container.mainContext, now: now, calendar: calendar)
        XCTAssertFalse(viewModel.todayConversationIsAvailable)

        let identity = OnboardingConversationIdentity(
            scenarioID: "daily_q003",
            playbackKey: "daily:onboarding:daily_q003"
        )
        viewModel.offerDeferredOnboardingConversationIfNeeded(
            identity: identity,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(viewModel.todayConversationIsAvailable)

        XCTAssertTrue(
            viewModel.openOnboardingConversation(
                identity: identity,
                now: now,
                calendar: calendar
            )
        )
        XCTAssertEqual(viewModel.activeLaunch?.scenario.scenarioId, "daily_q003")
        XCTAssertEqual(viewModel.activeLaunch?.playbackKey, "daily:onboarding:daily_q003")
    }

    func testDateSpecificIdentityOpensOriginalPlaybackKeyFromNextDayCard() throws {
        let schema = Schema([
            Routine.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let nextDay = try date(2026, 9, 21, 12, 0)
        let identity = OnboardingConversationIdentity(
            scenarioID: "daily_q003",
            playbackKey: "daily:2026-09-20"
        )
        let viewModel = InteractionViewModel()

        viewModel.configure(context: container.mainContext, now: nextDay, calendar: calendar)
        viewModel.offerDeferredOnboardingConversationIfNeeded(
            identity: identity,
            now: nextDay,
            calendar: calendar
        )

        XCTAssertTrue(
            viewModel.openOnboardingConversation(
                identity: identity,
                now: nextDay,
                calendar: calendar
            )
        )
        XCTAssertEqual(viewModel.activeLaunch?.scenario.scenarioId, "daily_q003")
        XCTAssertEqual(viewModel.activeLaunch?.playbackKey, "daily:2026-09-20")
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
