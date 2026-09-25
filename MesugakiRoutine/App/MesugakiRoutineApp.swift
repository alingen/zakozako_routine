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
    private let usesIsolatedStorySample: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRecordedCurrentActivation = false

    init() {
        let schema = Schema([
            Routine.self,
            BlockedBehavior.self,
            UserActionEvent.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        // Xcode Canvas also initializes the app entry point before replacing its
        // scene with the selected preview. Keep that bootstrap store ephemeral so
        // previews never depend on a stale or unavailable on-disk SwiftData store.
        let isRunningForPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #if DEBUG
        let isTransitionSample = ProcessInfo.processInfo.arguments.contains("--color-slide-sample")
        #else
        let isTransitionSample = false
        #endif
        usesIsolatedStorySample = isTransitionSample
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningForPreviews || isTransitionSample
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
            appContent
                .environment(SiriLaunchCoordinator.shared)
                .task {
                    guard !usesIsolatedStorySample else { return }
                    if scenePhase == .active && !hasRecordedCurrentActivation {
                        recordAppOpen()
                    }
                    synchronizeScreenTimeBehavior()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) {
            guard !usesIsolatedStorySample else { return }
            guard scenePhase == .active else {
                hasRecordedCurrentActivation = false
                return
            }
            if !hasRecordedCurrentActivation {
                recordAppOpen()
            }
            synchronizeScreenTimeBehavior()
            rescheduleNotifications()
        }
    }

    private func recordAppOpen() {
        // 初回の .task と scenePhase 変更が重なっても、同じ active 期間は1件だけ記録する。
        do {
            try UserActionEventRepository(context: modelContainer.mainContext).record(.appOpened)
            hasRecordedCurrentActivation = true
        } catch {
            // 書き込み失敗時は次の active 通知で再試行できるようにする。
            hasRecordedCurrentActivation = false
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--color-slide-sample") {
            StorySceneTransitionSample()
        } else {
            RootTabView()
        }
        #else
        RootTabView()
        #endif
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
