import Foundation

/// 新しい約束を作るときに選べる入力済みテンプレート。
/// プリセット自体は保存せず、選択時に編集画面の下書きへ値をコピーする。
struct RoutinePreset: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let period: HabitPeriod
    let targetCount: Int
    /// タイマーで取り組む目標分数。nil のプリセットは通常の約束として扱う。
    let targetDurationMinutes: Int?

    init(
        id: String,
        title: String,
        iconName: String,
        period: HabitPeriod = .day,
        targetCount: Int = 1,
        targetDurationMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.period = period
        self.targetCount = max(targetCount, 1)
        self.targetDurationMinutes = targetDurationMinutes.map { max($0, 1) }
    }

    /// よく始められる約束。タイトルとアイコンは選択後の確認画面で変更できる。
    static let recommended: [RoutinePreset] = [
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

    /// 後からタイマーを開始するための約束。現時点では目標分数までを保存する。
    static let timer: [RoutinePreset] = [
        RoutinePreset(
            id: "timer-read-book",
            title: "本を読む",
            iconName: "book",
            targetDurationMinutes: 10
        ),
        RoutinePreset(
            id: "timer-tidy-up",
            title: "整頓をする",
            iconName: "sparkles",
            targetDurationMinutes: 10
        ),
        RoutinePreset(
            id: "timer-exercise",
            title: "運動する",
            iconName: "figure.run",
            targetDurationMinutes: 10
        ),
        RoutinePreset(
            id: "timer-meditate",
            title: "瞑想をする",
            iconName: "figure.mind.and.body",
            targetDurationMinutes: 10
        ),
    ]

    /// 初回オンボーディングで、最初の約束として提示する候補。
    /// 達成条件は次の画面で決めるため、ここではタイマー時間を設定しない。
    /// 通常の追加画面に同じ候補を重複表示しないよう `all` には含めない。
    static let onboarding: [RoutinePreset] = [
        RoutinePreset(
            id: "onboarding-strength-training",
            title: "筋トレをする",
            iconName: "figure.strengthtraining.traditional"
        ),
        RoutinePreset(
            id: "onboarding-walk",
            title: "散歩をする",
            iconName: "figure.walk"
        ),
        RoutinePreset(
            id: "onboarding-study",
            title: "勉強する",
            iconName: "graduationcap"
        ),
        RoutinePreset(
            id: "onboarding-journal",
            title: "日記をつける",
            iconName: "pencil.and.outline"
        ),
        RoutinePreset(
            id: "onboarding-read-book",
            title: "本を読む",
            iconName: "book"
        ),
        RoutinePreset(
            id: "onboarding-tidy-up",
            title: "部屋を片付ける",
            iconName: "sparkles"
        ),
    ]

    static let all: [RoutinePreset] = recommended + timer
}
