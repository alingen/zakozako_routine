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
            id: "strength-training",
            title: "筋トレをする",
            iconName: "figure.strengthtraining.traditional"
        ),
        RoutinePreset(
            id: "walk",
            title: "散歩をする",
            iconName: "figure.walk"
        ),
        RoutinePreset(
            id: "stretch",
            title: "ストレッチをする",
            iconName: "figure.cooldown"
        ),
        RoutinePreset(
            id: "journal",
            title: "日記を書く",
            iconName: "pencil.and.outline"
        ),
        RoutinePreset(
            id: "study",
            title: "勉強する",
            iconName: "graduationcap"
        ),
        RoutinePreset(
            id: "tidy-up",
            title: "片づける",
            iconName: "sparkles"
        ),
        RoutinePreset(
            id: "take-vitamins",
            title: "ビタミンを飲む",
            iconName: "pills"
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

/// 最初の約束を具体化するときに選ぶ量。選択後は既存の下書きへ表示名とタイトルを保存する。
struct OnboardingGoalPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let routineTitle: String

    static func options(for habitID: String?) -> [Self] {
        switch habitID {
        case "onboarding-strength-training":
            return durationOptions([1, 10, 30]) { "筋トレを\($0)分する" }
        case "onboarding-walk":
            return durationOptions([10, 20, 30]) { "\($0)分散歩をする" }
        case "onboarding-study":
            return durationOptions([10, 20, 30]) { "\($0)分勉強する" }
        case "onboarding-journal":
            return [1, 3, 5].map { lines in
                Self(
                    id: "lines-\(lines)",
                    label: "\(lines)行",
                    routineTitle: "日記を\(lines)行書く"
                )
            }
        case "onboarding-read-book":
            return durationOptions([5, 15, 30]) { "本を\($0)分読む" }
        case "onboarding-tidy-up":
            return durationOptions([1, 5, 10]) { "\($0)分部屋を片付ける" }
        default:
            return []
        }
    }

    private static func durationOptions(
        _ minutes: [Int],
        routineTitle: (Int) -> String
    ) -> [Self] {
        minutes.map { minutes in
            Self(
                id: "minutes-\(minutes)",
                label: "\(minutes)分",
                routineTitle: routineTitle(minutes)
            )
        }
    }
}
