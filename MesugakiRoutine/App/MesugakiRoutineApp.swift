import SwiftUI
import SwiftData

@main
struct MesugakiRoutineApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Routine.self,
            RoutineStep.self,
            RoutineSession.self,
            RoutineEvent.self,
            CharacterPreset.self,
            BlockedBehavior.self,
        ])
        let configuration = ModelConfiguration(schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        DataSeeder.seedIfNeeded(context: modelContainer.mainContext)
        LocalSecretsSeeder.seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(SiriLaunchCoordinator.shared)
                .onOpenURL { url in
                    SiriLaunchCoordinator.shared.handle(url: url)
                }
        }
        .modelContainer(modelContainer)
    }
}
