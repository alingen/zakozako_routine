import Foundation

/// App Intents(「Hey Siri、小悪魔コーチで朝ルーティンを開始」)経由でアプリが開かれたことを
/// UI側(HomeView)に伝えるための小さな状態保持クラス。
///
/// `AppIntent.perform()` は SwiftUI の環境値にアクセスできないため、App全体で1つだけの `shared`
/// シングルトンとして持ち、App起動時に同じインスタンスを `.environment(...)` へも注入する。
/// 実際のセッション開始は、フォアグラウンドに来た `HomeView` が通常のルーティン開始処理を使って行う。
@Observable
@MainActor
final class SiriLaunchCoordinator {
    static let shared = SiriLaunchCoordinator()

    /// App Intent側から指定された、開始すべきルーティンの種別。
    /// HomeView側が読み取ったら nil に戻す想定。
    var pendingRoutineTypeToStart: RoutineType?

    func requestStart(routineType: RoutineType) {
        pendingRoutineTypeToStart = routineType
    }
}
