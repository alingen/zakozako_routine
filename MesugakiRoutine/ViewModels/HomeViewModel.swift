import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class HomeViewModel {
    private(set) var morningRoutine: Routine?
    private(set) var nightRoutine: Routine?

    private var dependencies: AppDependencies?

    func configure(context: ModelContext) {
        if dependencies == nil {
            dependencies = AppDependencies(context: context)
        }
        reload()
    }

    func reload() {
        guard let dependencies else { return }
        morningRoutine = dependencies.routineRepository.fetch(type: .morning).first
        nightRoutine = dependencies.routineRepository.fetch(type: .night).first
    }
}
