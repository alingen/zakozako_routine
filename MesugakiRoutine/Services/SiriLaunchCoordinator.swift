import Foundation

/// 「Hey Siri」/ App Intents 経由でアプリが開かれたことをUI側(HomeView)に伝えるための小さな状態保持クラス。
///
/// 2つの経路がある。
/// 1. ショートカットの「URLを開く」で `zakozakoroutine://` を開いてもらう経路(ルーティン種別を指定しない、
///    汎用の「開く→数秒だけ音声で聞く」フロー)。
/// 2. `StartRoutineIntent`(App Intents)経由で、Siri/ショートカットから直接「どのルーティンか」を
///    指定して開く経路。こちらは音声認識なしで即座にルーティンが決まる。
///
/// `AppIntent.perform()` は SwiftUI の環境値にアクセスできないため、App全体で1つだけの `shared`
/// シングルトンとして持ち、App起動時に同じインスタンスを `.environment(...)` へも注入する。
@Observable
@MainActor
final class SiriLaunchCoordinator {
    static let shared = SiriLaunchCoordinator()
    static let urlScheme = "zakozakoroutine"

    /// trueの間、HomeViewが次に表示されたタイミングで自動リスニングを開始する。
    /// 一度読み取ったら呼び出し側が false に戻す想定(再表示のたびに毎回発火しないように)。
    var shouldAutoListenOnNextHomeAppear = false

    /// App Intent側から指定された、開始すべきルーティンの種別。
    /// HomeView側が読み取ったら nil に戻す想定。
    var pendingRoutineTypeToStart: RoutineType?

    func handle(url: URL) {
        guard url.scheme == Self.urlScheme else { return }
        shouldAutoListenOnNextHomeAppear = true
    }

    func requestStart(routineType: RoutineType) {
        pendingRoutineTypeToStart = routineType
    }
}
