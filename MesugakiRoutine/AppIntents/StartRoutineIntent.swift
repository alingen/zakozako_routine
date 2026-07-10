import AppIntents

/// ショートカット上でユーザーが選べる「朝/夜」のパラメータ。
enum RoutineKindParameter: String, AppEnum {
    case morning
    case night

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "ルーティン種別" }
    static var caseDisplayRepresentations: [RoutineKindParameter: DisplayRepresentation] {
        [
            .morning: "朝ルーティン",
            .night: "夜ルーティン",
        ]
    }

    var routineType: RoutineType {
        switch self {
        case .morning: return .morning
        case .night: return .night
        }
    }
}

/// 「ショートカット」アプリの操作一覧から選べる、ルーティン開始アクション。
///
/// `perform()` はSwiftUIの外(App Intentsのランタイム)で実行されるため、SwiftDataやAppDependenciesには
/// 直接触れず、`SiriLaunchCoordinator` に「どのルーティンを開始したいか」を伝えるだけにとどめている。
/// 実際のセッション開始は、フォアグラウンドに来た `HomeView` が既存のルーティン開始処理(`ConversationCoordinator`)
/// を使って行う。こうすることで、ボタン操作時と全く同じ経路を通り、二重実装を避けられる。
struct StartRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "ルーティンを開始する"
    static var description = IntentDescription("小悪魔コーチの朝ルーティンまたは夜ルーティンを開始します。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "ルーティン")
    var routineKind: RoutineKindParameter

    init() {
        routineKind = .morning
    }

    init(routineKind: RoutineKindParameter) {
        self.routineKind = routineKind
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriLaunchCoordinator.shared.requestStart(routineType: routineKind.routineType)
        return .result()
    }
}
