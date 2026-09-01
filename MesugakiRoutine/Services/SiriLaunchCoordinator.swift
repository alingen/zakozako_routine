import Foundation

/// App Intent(「Hey Siri、小悪魔コーチで今日のルーティンを開く」)経由でアプリが開かれたことを
/// UI側(HomeView)に伝えるための小さな状態保持クラス。
///
/// `AppIntent.perform()` は SwiftUI の環境値にアクセスできないため、App全体で1つだけの `shared`
/// シングルトンとして持ち、App起動時に同じインスタンスを `.environment(...)` へも注入する。
/// 実際の画面遷移は、フォアグラウンドに来た `HomeView` が通常のルーティン開始処理を使って行う。
@Observable
@MainActor
final class SiriLaunchCoordinator {
    static let shared = SiriLaunchCoordinator()

    /// 中立 App Intent「今日のルーティンを開く」から立てられるフラグ。
    /// HomeView 側が読み取ったら false に戻す想定。
    var pendingOpenTodayRoutines = false

    func requestOpenTodayRoutines() {
        pendingOpenTodayRoutines = true
    }
}
