import Foundation
import SwiftData
import Observation

struct RecentLogItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let date: Date
}

extension RoutineEventType {
    var displayText: String {
        switch self {
        case .started: return "ルーティン開始"
        case .completedStep: return "ステップ完了"
        case .skippedStep: return "ステップスキップ"
        case .failedStep: return "ステップ失敗"
        case .blockedBehavior: return "やらないこと検知"
        case .completedRoutine: return "ルーティン全完了"
        case .abandoned: return "ルーティン中断"
        }
    }
}

@Observable
@MainActor
final class RoutineLogViewModel {
    private(set) var logs: [RecentLogItem] = []

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        let stepTitles: [UUID: String] = dependencies.routineRepository.fetchAll()
            .flatMap(\.steps)
            .reduce(into: [:]) { result, step in result[step.id] = step.title }

        logs = dependencies.routineEngine.recentEvents(limit: 100).map { event in
            RecentLogItem(
                id: event.id,
                title: event.eventType.displayText,
                subtitle: event.stepId.flatMap { stepTitles[$0] } ?? "",
                date: event.createdAt
            )
        }
    }
}
