import SwiftUI
import SwiftData

@main
struct MesugakiRoutineApp: App {
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Routine.self,
            RoutineStep.self,
            RoutineSession.self,
            RoutineEvent.self,
            CharacterPreset.self,
            BlockedBehavior.self,
            TrustState.self,
            UserProfileFact.self,
            FreeTalkTopicProgress.self,
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
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            rescheduleNotifications()
        }
    }

    /// アプリがフォアグラウンドに戻るたびに、日付が変わっている場合の再スケジュールを保証する。
    /// (Home画面が再表示されない限り呼ばれない `HomeViewModel.reload()` を補う)
    private func rescheduleNotifications() {
        let dependencies = AppDependencies(context: modelContainer.mainContext)
        let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
        Task {
            await dependencies.notificationScheduler.reschedule(
                routines: routines,
                sessionRepository: dependencies.sessionRepository
            )
        }
    }
}
