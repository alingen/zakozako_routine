import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class ZakoBulletinTests: XCTestCase {
    private func post(_ title: String = "本を読む", date: Date = .now) -> ZakoNewsPost {
        ZakoNewsPost(id: UUID(), kind: "achievement", displayName: "テスト", taskTitle: title,
            comment: "", occurredAt: date, createdAt: date, isMine: false,
            cheerCount: 0, teaseCount: 0, strongCount: 0, myReaction: nil)
    }

    func testRotationIsNewestInFrontAndNeverRepeats() {
        let posts = (0..<5).map { post("\($0)") }
        var rotation = ZakoNewsRotation()
        rotation.append(posts)
        XCTAssertEqual(rotation.visible.map(\.id), Array(posts.prefix(3)).map(\.id))
        rotation.advance()
        XCTAssertEqual(rotation.visible.map(\.id), [posts[3], posts[0], posts[1]].map(\.id))
        rotation.advance()
        let stable = [posts[4], posts[3], posts[0]].map(\.id)
        rotation.append(posts); rotation.advance()
        XCTAssertEqual(rotation.visible.map(\.id), stable)
        XCTAssertEqual(rotation.seen.count, 5)
    }

    func testShowFirstPutsOwnPostInFrontWithoutDuplicatesOrGrowing() {
        let posts = (0..<5).map { post("\($0)") }
        var rotation = ZakoNewsRotation()
        rotation.append(posts)
        let mine = post("自分")
        rotation.showFirst(mine)
        XCTAssertEqual(rotation.visible.map(\.id), [mine, posts[0], posts[1]].map(\.id))
        // すでに待ち行列にある投稿を先頭に出しても、二重に並ばない。
        rotation.showFirst(posts[3])
        XCTAssertEqual(rotation.visible.map(\.id), [posts[3], mine, posts[0]].map(\.id))
        XCTAssertFalse(rotation.pending.contains { $0.id == posts[3].id })
        rotation.advance()
        XCTAssertEqual(rotation.visible.first?.id, posts[4].id)
    }

    func testRotationReconciliationRemovesBlockedDeletedAndHidden() {
        let posts = (0..<8).map { post("\($0)") }
        var rotation = ZakoNewsRotation(); rotation.append(posts)
        rotation.reconcile([posts[0], posts[2], posts[4]])
        XCTAssertEqual(rotation.visible.map(\.id), [posts[0], posts[2]].map(\.id))
        XCTAssertEqual(rotation.pending.map(\.id), [posts[4].id])
        rotation.advance()
        XCTAssertEqual(rotation.visible.count, 3)
    }

    func testRotationBoundsPausedBufferAndExpiresPosts() {
        var rotation = ZakoNewsRotation()
        rotation.append((0..<100).map { _ in post() })
        XCTAssertLessThanOrEqual(rotation.pending.count + rotation.visible.count, 43)
        rotation.expire(now: .now.addingTimeInterval(ZakoNewsConfiguration.retentionSeconds + 1))
        XCTAssertTrue(rotation.visible.isEmpty); XCTAssertTrue(rotation.pending.isEmpty)
    }

    func testPublicTextValidation() {
        XCTAssertTrue(ZakoNewsText.isValid(String(repeating: "あ", count: 30), limit: 30))
        XCTAssertFalse(ZakoNewsText.isValid(String(repeating: "あ", count: 31), limit: 30))
        for text in ["a\nb", "a\rb", "https://example.com", "www.example.com", "example.com/path"] {
            XCTAssertFalse(ZakoNewsText.isValid(text, limit: 80), text)
        }
        XCTAssertFalse(ZakoNewsText.isValid("   ", limit: 30))
        XCTAssertTrue(ZakoNewsText.isValid("", limit: 30, allowEmpty: true))
    }

    func testSharingDefaultsOffAndPersistsInExistingModels() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repo = RoutineRepository(context: context)
        let routine = try repo.create(title: "本を読む")
        let blocked = try XCTUnwrap(BlockedBehaviorRepository(context: context).create(title: "SNS"))
        XCTAssertFalse(routine.shareToZakoNews); XCTAssertFalse(blocked.shareToZakoNews)
        routine.shareToZakoNews = true; blocked.shareToZakoNews = true; try context.save()
        let verified = ModelContext(container)
        XCTAssertTrue(try XCTUnwrap(verified.fetch(FetchDescriptor<Routine>()).first).shareToZakoNews)
        XCTAssertTrue(try XCTUnwrap(verified.fetch(FetchDescriptor<BlockedBehavior>()).first).shareToZakoNews)
        XCTAssertTrue(RoutineEditViewModel(routine: routine).shareToZakoNews)
        XCTAssertTrue(BlockedBehaviorDraft(behavior: blocked).shareToZakoNews)
    }

    func testPublicationRequiresCompleteTargetAndSamePeriodIsIdempotent() throws {
        let now = Date.now
        let routine = Routine(title: "読む", createdAt: now.addingTimeInterval(-60), targetCount: 3)
        XCTAssertNil(ZakoNewsPublication.achievement(routine, now: now))
        routine.shareToZakoNews = true
        routine.progressEvents = [now, now]
        XCTAssertNil(ZakoNewsPublication.achievement(routine, now: now))
        routine.progressEvents.append(now)
        let first = try XCTUnwrap(ZakoNewsPublication.achievement(routine, now: now))
        let second = try XCTUnwrap(ZakoNewsPublication.achievement(routine, now: now.addingTimeInterval(1)))
        XCTAssertEqual(first.sourceKey, second.sourceKey)
    }

    func testNetworkFailureDoesNotUndoRecordsAndExplicitFailurePostsBelowLimit() async throws {
        let container = try makeContainer()
        let backend = MockNewsBackend(); backend.fails = true
        let (store, defaults, suite) = makeStore(backend)
        defer { defaults.removePersistentDomain(forName: suite) }
        let context = container.mainContext
        let routine = try RoutineRepository(context: context).create(title: "本を読む", shareToZakoNews: true)
        let blocked = try XCTUnwrap(BlockedBehaviorRepository(context: context).create(title: "SNS", limitCount: 3, shareToZakoNews: true))
        let home = HomeViewModel(news: store); home.configure(context: context)
        XCTAssertTrue(home.advanceRoutine(routine))
        XCTAssertTrue(home.recordPromiseFailure(blocked))
        await store.sendPending()
        XCTAssertEqual(routine.progressEvents.count, 1)
        XCTAssertEqual(blocked.usageEvents.count, 1)
        XCTAssertEqual(store.pendingPublications.count, 2)
        XCTAssertNotNil(store.errorMessage)
        home.reload(); home.reload()
        XCTAssertEqual(store.pendingPublications.count, 2, "Loading must not publish")
        let restored = ZakoNewsStore(repository: backend, defaults: defaults)
        XCTAssertEqual(restored.pendingPublications.map(\.sourceKey), store.pendingPublications.map(\.sourceKey))
        backend.fails = false
        await store.sendPending()
        XCTAssertTrue(store.pendingPublications.isEmpty)
        XCTAssertEqual(backend.published.count, 2)
    }

    func testShareOffAndAutomaticScreenTimeDoNotPublish() throws {
        let container = try makeContainer()
        let backend = MockNewsBackend()
        let (store, defaults, suite) = makeStore(backend)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = RoutineRepository(context: container.mainContext)
        let routine = try repo.create(title: "本を読む")
        let home = HomeViewModel(news: store); home.configure(context: container.mainContext)
        XCTAssertTrue(home.advanceRoutine(routine)); XCTAssertTrue(store.pendingPublications.isEmpty)
        let blockedRepo = BlockedBehaviorRepository(context: container.mainContext)
        let behavior = try XCTUnwrap(blockedRepo.create(title: "スマホ", trackingKind: .screenTime, shareToZakoNews: true))
        let now = Date.now
        try blockedRepo.recordScreenTimeSignal(.init(behaviorID: behavior.id, appDayStart: AppDay.startOfDay(for: now),
            occurredAt: now, kind: .thresholdExceeded), for: behavior)
        home.reload()
        XCTAssertTrue(store.pendingPublications.isEmpty)
    }

    func testRotationNeverFetchesAndRefreshIsThrottled() async {
        let backend = MockNewsBackend(); backend.posts = (0..<20).map { _ in post() }
        let (store, defaults, suite) = makeStore(backend)
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refreshIfNeeded()
        for _ in 0..<100 { store.rotate(); await store.refreshIfNeeded() }
        XCTAssertEqual(backend.feedCalls, 1)
    }

    func testDeletingRoutineCancelsOnlyItsUnsentPublication() async throws {
        let container = try makeContainer()
        let backend = MockNewsBackend(); backend.fails = true
        let (store, defaults, suite) = makeStore(backend)
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = RoutineRepository(context: container.mainContext)
        let first = try repo.create(title: "本を読む", shareToZakoNews: true)
        let second = try repo.create(title: "勉強する", shareToZakoNews: true)
        let home = HomeViewModel(news: store); home.configure(context: container.mainContext)
        XCTAssertTrue(home.advanceRoutine(first))
        XCTAssertTrue(home.advanceRoutine(second))
        await store.sendPending()
        home.deleteRoutine(first)
        XCTAssertEqual(store.pendingPublications.map(\.itemID), [second.id])
        let restored = ZakoNewsStore(repository: backend, defaults: defaults)
        XCTAssertEqual(restored.pendingPublications.map(\.itemID), [second.id])
    }

    private func makeStore(_ backend: MockNewsBackend) -> (ZakoNewsStore, UserDefaults, String) {
        let suite = "ZakoNewsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        return (ZakoNewsStore(repository: backend, defaults: defaults), defaults, suite)
    }
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Routine.self, BlockedBehavior.self, UserActionEvent.self,
            StoryEventProgress.self, StoryPlaybackProgress.self, StoryProfileValue.self, StoryMemoryUnlock.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}

@MainActor private final class MockNewsBackend: ZakoNewsServing {
    var fails = false
    var feedCalls = 0
    var posts: [ZakoNewsPost] = []
    var published: [String: UUID] = [:]
    func feed(before: ZakoNewsPost?, ids: [UUID]?, mine: Bool) async throws -> [ZakoNewsPost] {
        feedCalls += 1
        if fails { throw URLError(.notConnectedToInternet) }
        return posts
    }
    func publish(_ publication: ZakoNewsPublication) async throws -> UUID {
        if fails { throw URLError(.notConnectedToInternet) }
        let id = published[publication.id] ?? UUID(); published[publication.id] = id; return id
    }
    func comment(postID: UUID, text: String) async throws {}
    func react(postID: UUID, reaction: String?) async throws {}
    func report(postID: UUID, reason: String) async throws {}
    func block(postID: UUID) async throws {}
    func delete(postID: UUID) async throws {}
    func blocks() async throws -> [ZakoNewsBlock] { [] }
    func unblock(blockID: UUID) async throws {}
}
