import AppIntents

/// アプリインストール時にOSへ自動登録される既定のSiriフレーズ。
/// これにより、ユーザーがショートカットを作らなくても
/// 「Hey Siri、小悪魔コーチで今日のルーティンを開く」がそのまま動く。
struct MesugakiRoutineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayRoutinesIntent(),
            phrases: [
                "\(.applicationName)で今日のルーティンを開く",
                "\(.applicationName)でルーティンを始める",
                "\(.applicationName)でルーティン開始して",
            ],
            shortTitle: "今日のルーティンを開く",
            systemImageName: "checklist"
        )
    }
}
