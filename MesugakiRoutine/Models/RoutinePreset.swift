import Foundation

/// 新しい約束を作るときに選べる入力済みテンプレート。
/// プリセット自体は保存せず、選択時に編集画面の下書きへ値をコピーする。
struct RoutinePreset: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let period: HabitPeriod
    let targetCount: Int

    init(
        id: String,
        title: String,
        iconName: String,
        period: HabitPeriod = .day,
        targetCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.period = period
        self.targetCount = max(targetCount, 1)
    }

    /// よく始められる約束。タイトルとアイコンは選択後の確認画面で変更できる。
    static let all: [RoutinePreset] = [
        RoutinePreset(
            id: "healthy-meal",
            title: "健康的な食事をとる",
            iconName: "carrot"
        ),
        RoutinePreset(
            id: "find-good-things",
            title: "いいことを3つ見つける",
            iconName: "heart"
        ),
        RoutinePreset(
            id: "journal",
            title: "日記を書く",
            iconName: "pencil.and.outline"
        ),
        RoutinePreset(
            id: "study",
            title: "勉強する",
            iconName: "book"
        ),
        RoutinePreset(
            id: "walk-dog",
            title: "犬を散歩させる",
            iconName: "dog"
        ),
        RoutinePreset(
            id: "drink-water",
            title: "水を飲む",
            iconName: "drop"
        ),
        RoutinePreset(
            id: "take-vitamins",
            title: "ビタミンを飲む",
            iconName: "pills"
        ),
        RoutinePreset(
            id: "take-photo",
            title: "写真を撮る",
            iconName: "camera"
        ),
        RoutinePreset(
            id: "walk",
            title: "散歩する",
            iconName: "figure.walk"
        ),
        RoutinePreset(
            id: "stretch",
            title: "ストレッチする",
            iconName: "figure.cooldown"
        ),
        RoutinePreset(
            id: "strength-training",
            title: "筋トレする",
            iconName: "figure.strengthtraining.traditional"
        ),
        RoutinePreset(
            id: "sleep-early",
            title: "早く寝る",
            iconName: "bed.double"
        ),
    ]
}
