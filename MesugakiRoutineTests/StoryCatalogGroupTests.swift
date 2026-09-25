import XCTest
@testable import MesugakiRoutine

final class StoryCatalogGroupTests: XCTestCase {
    private func story(
        _ id: String,
        episode: Int,
        background: String? = nil,
        isUnlocked: Bool = true,
        isNew: Bool = false,
        isRead: Bool = false,
        conditions: [StoryConditionPresentation] = []
    ) -> StoryListItemPresentation {
        StoryListItemPresentation(
            id: id, title: id, chapterId: "chapter_01", episodeOrder: episode,
            backgroundAssetId: background, isUnlocked: isUnlocked, isNew: isNew,
            isRead: isRead, conditions: conditions
        )
    }

    func testPrologueIsSplitIntoItsOwnEntryBeforeTheChapter() {
        let chapter = StoryChapterPresentation(
            id: "chapter_01",
            title: "チャプター 01",
            stories: [
                story("prologue", episode: 0, background: "bg_room", isRead: true),
                story("ep1", episode: 1, isRead: true),
                story("ep2", episode: 2, isNew: true),
            ]
        )

        let groups = StoryCatalogGroup.groups(from: [chapter])

        XCTAssertEqual(groups.map(\.title), ["プロローグ", "チャプター 01"])
        XCTAssertEqual(groups[0].stories.map(\.id), ["prologue"])
        XCTAssertEqual(groups[0].thumbnailAssetId, "bg_room")
        XCTAssertEqual(groups[1].stories.map(\.id), ["ep1", "ep2"])
        XCTAssertEqual(groups[1].readCount, 1)
        XCTAssertTrue(groups[1].hasNew)
    }

    func testLaterChapterProloguesNameTheirChapter() {
        let chapters = [
            StoryChapterPresentation(id: "chapter_01", title: "チャプター 01", stories: [story("a", episode: 1)]),
            StoryChapterPresentation(id: "chapter_02", title: "チャプター 02", stories: [
                story("b", episode: 0), story("c", episode: 1),
            ]),
        ]

        let titles = StoryCatalogGroup.groups(from: chapters).map(\.title)

        XCTAssertEqual(titles, ["チャプター 01", "チャプター 02 プロローグ", "チャプター 02"])
    }

    func testLockedChapterShowsTheFirstUnmetCondition() {
        let condition = StoryConditionPresentation(
            id: "days", text: "約束を累計5日達成", currentValue: "2", targetValue: "5", isSatisfied: false
        )
        let chapter = StoryChapterPresentation(
            id: "chapter_02",
            title: "チャプター 02",
            stories: [
                story("a", episode: 1, isUnlocked: false, conditions: [condition]),
                story("b", episode: 2, isUnlocked: false),
            ]
        )

        let group = StoryCatalogGroup.groups(from: [chapter])[0]

        XCTAssertFalse(group.isUnlocked)
        XCTAssertEqual(group.unlockHint, "約束を累計5日達成")
    }
}
