import SwiftUI
import SwiftData
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

@MainActor
enum AppOrientationController {
    static func set(_ orientations: UIInterfaceOrientationMask) {
        AppDelegate.supportedOrientations = orientations

        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in activeScenes {
            scene.windows
                .first(where: \.isKeyWindow)?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: orientations)
            )
        }
    }
}

@main
struct MesugakiRoutineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Routine.self,
            BlockedBehavior.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        // Xcode Canvas also initializes the app entry point before replacing its
        // scene with the selected preview. Keep that bootstrap store ephemeral so
        // previews never depend on a stale or unavailable on-disk SwiftData store.
        let isRunningForPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningForPreviews
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        DataSeeder.seedIfNeeded(context: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(SiriLaunchCoordinator.shared)
                .task {
                    synchronizeScreenTimeBehavior()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            synchronizeScreenTimeBehavior()
            rescheduleNotifications()
        }
    }

    /// アプリがフォアグラウンドに戻るたびに、日付が変わっている場合の再スケジュールを保証する。
    /// (Home画面が再表示されない限り呼ばれない `HomeViewModel.reload()` を補う)
    private func rescheduleNotifications() {
        let dependencies = AppDependencies(context: modelContainer.mainContext)
        let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
        Task {
            await dependencies.notificationScheduler.reschedule(routines: routines)
        }
    }

    /// Device Activity拡張がアプリ外で検知した上限超過を取り込み、監視状態も復元する。
    private func synchronizeScreenTimeBehavior() {
        let dependencies = AppDependencies(context: modelContainer.mainContext)
        dependencies.screenTimeMonitoringService.consumePendingSignals(
            using: dependencies.blockedBehaviorRepository
        )

        guard let behavior = dependencies.blockedBehaviorRepository.fetchActive() else { return }
        if behavior.trackingKind == .screenTime {
            // Screen Time は拡張機能が監視完了を確認した日だけ達成として取り込む。
            try? dependencies.screenTimeMonitoringService.ensureMonitoring(for: behavior)
        } else {
            dependencies.blockedBehaviorRepository.autoEvaluate(behavior)
        }
        if behavior.masteredAt != nil {
            dependencies.screenTimeMonitoringService.stopMonitoring(for: behavior)
        }
    }
}
