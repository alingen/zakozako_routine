import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RoutineListViewModel {
    private(set) var routines: [Routine] = []
    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        routines = dependencies.routineRepository.fetchAll()
    }

    func delete(_ routine: Routine) {
        guard let dependencies else { return }
        dependencies.routineRepository.delete(routine)
        reload()
    }
}
