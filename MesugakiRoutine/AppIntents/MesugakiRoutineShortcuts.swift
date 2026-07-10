import AppIntents

/// アプリインストール時にOSへ自動登録される既定のSiriフレーズ。
/// これにより、ユーザーがショートカットを作らなくても
/// 「Hey Siri、小悪魔コーチで朝ルーティンを開始」がそのまま動く。
/// (「ざこざこルーティン」のような独自フレーズにしたい場合は、引き続き
/// ショートカットアプリでこの `StartRoutineIntent` を選んでカスタムフレーズを設定できる)
struct MesugakiRoutineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRoutineIntent(routineKind: .morning),
            phrases: [
                "\(.applicationName)で朝ルーティンを開始",
                "\(.applicationName)で朝ルーティン開始して",
            ],
            shortTitle: "朝ルーティン開始",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: StartRoutineIntent(routineKind: .night),
            phrases: [
                "\(.applicationName)で夜ルーティンを開始",
                "\(.applicationName)で夜ルーティン開始して",
            ],
            shortTitle: "夜ルーティン開始",
            systemImageName: "moon.stars.fill"
        )
    }
}
