import Foundation

enum StoryContentRepositoryError: LocalizedError, Equatable {
    case resourceNotFound(String)
    case unreadableResource(String)
    case decodingFailed(String)
    case duplicateScenarioId(String)
    case duplicateChoiceGroupId(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Story content resource \(name) was not found."
        case .unreadableResource(let name):
            return "Story content resource \(name) could not be read."
        case .decodingFailed(let detail):
            return "Story content could not be decoded: \(detail)"
        case .duplicateScenarioId(let id):
            return "Story content contains duplicate scenario id \(id)."
        case .duplicateChoiceGroupId(let id):
            return "Story content contains duplicate choice group id \(id)."
        }
    }
}

struct StoryCGCatalogEntry: Identifiable, Hashable {
    let assetId: String
    let scenarioId: String
    let eventId: String?
    let eventTitle: String?
    let chapterId: String?
    let episodeOrder: Int?
    let storyCategory: StoryCategory?

    var id: String { assetId }
}

/// Read-only indexed access to generated CMS content.
/// The generated JSON is a build artifact; this repository never writes it.
final class StoryContentRepository {
    static let defaultResourceName = "story_content.generated"

    private let scenariosById: [String: StoryScenario]
    private let choiceGroupsById: [String: StoryChoiceGroup]

    let events: [StoryEvent]
    let dailyScenarios: [StoryScenario]
    let cgCatalog: [StoryCGCatalogEntry]

    convenience init(
        bundle: Bundle = .main,
        resourceName: String = StoryContentRepository.defaultResourceName
    ) throws {
        let nestedURL = bundle.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "GeneratedScenarios"
        )
        guard let url = nestedURL ?? bundle.url(forResource: resourceName, withExtension: "json") else {
            throw StoryContentRepositoryError.resourceNotFound("\(resourceName).json")
        }
        guard let data = try? Data(contentsOf: url) else {
            throw StoryContentRepositoryError.unreadableResource(url.lastPathComponent)
        }
        try self.init(data: data)
    }

    convenience init(data: Data, decoder: JSONDecoder = JSONDecoder()) throws {
        let decoded: StoryContentBundle
        do {
            decoded = try decoder.decode(StoryContentBundle.self, from: data)
        } catch {
            throw StoryContentRepositoryError.decodingFailed(String(describing: error))
        }
        try self.init(content: decoded)
    }

    init(content: StoryContentBundle) throws {
        var scenarioIndex: [String: StoryScenario] = [:]
        for scenario in content.scenarios {
            guard scenarioIndex[scenario.scenarioId] == nil else {
                throw StoryContentRepositoryError.duplicateScenarioId(scenario.scenarioId)
            }
            scenarioIndex[scenario.scenarioId] = scenario
        }

        var choiceIndex: [String: StoryChoiceGroup] = [:]
        for group in content.choiceGroups {
            guard choiceIndex[group.choiceId] == nil else {
                throw StoryContentRepositoryError.duplicateChoiceGroupId(group.choiceId)
            }
            choiceIndex[group.choiceId] = group
        }

        scenariosById = scenarioIndex
        choiceGroupsById = choiceIndex
        events = content.events.sorted(by: Self.eventOrdering)
        dailyScenarios = content.scenarios
            .filter { $0.scenarioType == .daily }
            .sorted {
                $0.scenarioId.localizedStandardCompare($1.scenarioId) == .orderedAscending
            }
        cgCatalog = Self.makeCGCatalog(content: content, sortedEvents: events)
    }

    func scenario(id: String) -> StoryScenario? {
        scenariosById[id]
    }

    func choices(id: String) -> [StoryChoice] {
        (choiceGroupsById[id]?.choices ?? []).sorted {
            if $0.choiceOrder != $1.choiceOrder { return $0.choiceOrder < $1.choiceOrder }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    func event(id: String) -> StoryEvent? {
        events.first { $0.eventId == id }
    }

    func events(category: StoryCategory) -> [StoryEvent] {
        events.filter { $0.storyCategory == category }
    }

    func events(chapterId: String, category: StoryCategory? = nil) -> [StoryEvent] {
        events.filter { event in
            event.chapterId == chapterId && (category == nil || event.storyCategory == category)
        }
    }

    func chapterIds(category: StoryCategory? = nil) -> [String] {
        var seen = Set<String>()
        return events.compactMap { event in
            guard category == nil || event.storyCategory == category,
                  let chapterId = event.chapterId,
                  seen.insert(chapterId).inserted else {
                return nil
            }
            return chapterId
        }
    }

    private static func eventOrdering(_ lhs: StoryEvent, _ rhs: StoryEvent) -> Bool {
        let lhsCategory = categoryRank(lhs.storyCategory)
        let rhsCategory = categoryRank(rhs.storyCategory)
        if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }

        let lhsChapter = lhs.chapterId ?? ""
        let rhsChapter = rhs.chapterId ?? ""
        let chapterComparison = lhsChapter.localizedStandardCompare(rhsChapter)
        if chapterComparison != .orderedSame { return chapterComparison == .orderedAscending }

        let lhsEpisode = lhs.episodeOrder ?? Int.max
        let rhsEpisode = rhs.episodeOrder ?? Int.max
        if lhsEpisode != rhsEpisode { return lhsEpisode < rhsEpisode }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.eventId.localizedStandardCompare(rhs.eventId) == .orderedAscending
    }

    private static func categoryRank(_ category: StoryCategory?) -> Int {
        switch category {
        case .main: return 0
        case .sub: return 1
        case .unknown, .none: return 2
        }
    }

    private static func makeCGCatalog(
        content: StoryContentBundle,
        sortedEvents: [StoryEvent]
    ) -> [StoryCGCatalogEntry] {
        var eventByScenario: [String: StoryEvent] = [:]
        for event in sortedEvents where eventByScenario[event.entryScenarioId] == nil {
            eventByScenario[event.entryScenarioId] = event
        }

        var seen = Set<String>()
        var result: [StoryCGCatalogEntry] = []
        let scenarios = content.scenarios.sorted {
            $0.scenarioId.localizedStandardCompare($1.scenarioId) == .orderedAscending
        }
        for scenario in scenarios {
            let event = eventByScenario[scenario.scenarioId]
            for node in scenario.nodes.sorted(by: { $0.lineOrder < $1.lineOrder }) {
                guard isCGNode(node),
                      let assetId = cgAssetId(node),
                      !assetId.isEmpty,
                      seen.insert(assetId).inserted else {
                    continue
                }
                result.append(
                    StoryCGCatalogEntry(
                        assetId: assetId,
                        scenarioId: scenario.scenarioId,
                        eventId: event?.eventId,
                        eventTitle: event?.title,
                        chapterId: event?.chapterId,
                        episodeOrder: event?.episodeOrder,
                        storyCategory: event?.storyCategory
                    )
                )
            }
        }

        let eventOrder = Dictionary(
            uniqueKeysWithValues: sortedEvents.enumerated().map { ($0.element.eventId, $0.offset) }
        )
        return result.sorted { lhs, rhs in
            let lhsEvent = lhs.eventId.flatMap { eventOrder[$0] } ?? Int.max
            let rhsEvent = rhs.eventId.flatMap { eventOrder[$0] } ?? Int.max
            if lhsEvent != rhsEvent { return lhsEvent < rhsEvent }
            return lhs.assetId.localizedStandardCompare(rhs.assetId) == .orderedAscending
        }
    }

    private static func isCGNode(_ node: StoryNode) -> Bool {
        if node.cg != nil || node.uiVariant == .cg { return true }
        return node.command == "show_cg"
    }

    private static func cgAssetId(_ node: StoryNode) -> String? {
        node.cg ?? node.assetId ?? node.commandArgs?["asset_id"]?.stringValue
    }
}
