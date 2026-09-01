import AppIntents

/// アプリインストール時にOSへ自動登録される既定のSiriフレーズ。
/// これにより、ユーザーがショートカットを作らなくても
/// 「Hey Siri、小悪魔コーチで今日の約束を開く」がそのまま動く。
struct MesugakiRoutineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayRoutinesIntent(),
            phrases: [
                "\(.applicationName)で今日の約束を開く",
                "\(.applicationName)で約束を始める",
                "\(.applicationName)を開いて",
            ],
            shortTitle: "今日の約束を開く",
            systemImageName: "checklist"
        )
    }
}
