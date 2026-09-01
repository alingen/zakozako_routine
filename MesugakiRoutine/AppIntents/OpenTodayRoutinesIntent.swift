import AppIntents

/// 「ショートカット」アプリ / Siri から使う、朝夜に依存しない中立のルーティン導線。
///
/// `perform()` は SwiftUI の外(App Intents ランタイム)で走るため、SwiftData や AppDependencies には
/// 触れず、`SiriLaunchCoordinator` にフラグを立てるだけ。実際の画面遷移はフォアグラウンドに来た
/// `HomeView` が行う(通常のルーティン開始経路と同じ)。
struct OpenTodayRoutinesIntent: AppIntent {
    static var title: LocalizedStringResource = "今日のルーティンを開く"
    static var description = IntentDescription("小悪魔コーチを開いて、今日やるルーティンを表示します。")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLaunchCoordinator.shared.requestOpenTodayRoutines()
        return .result()
    }
}
