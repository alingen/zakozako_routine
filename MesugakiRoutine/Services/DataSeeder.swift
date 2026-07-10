import Foundation
import SwiftData

/// 初回起動時にサンプルデータ(朝/夜ルーティン、やらないことリスト、デフォルトキャラ)を投入する。
@MainActor
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        seedCharacterIfNeeded(context: context)
        seedRoutinesIfNeeded(context: context)
        seedBlockedBehaviorsIfNeeded(context: context)
        try? context.save()
    }

    private static func seedCharacterIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<CharacterPreset>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        context.insert(CharacterPreset.makeDefault())
    }

    private static func seedRoutinesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Routine>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let morning = Routine(title: "朝ルーティン", routineDescription: "1日を気持ちよく始めるための準備", type: .morning)
        context.insert(morning)
        [
            ("水を飲む", 1),
            ("カーテンを開ける", 1),
            ("歯を磨く", 3),
            ("顔を洗う", 2),
            ("着替える", 3),
            ("今日やることを1つ確認する", 2),
        ].enumerated().forEach { index, item in
            let step = RoutineStep(
                title: item.0,
                orderIndex: index,
                estimatedMinutes: item.1,
                routine: morning
            )
            context.insert(step)
        }

        let night = Routine(title: "夜ルーティン", routineDescription: "1日を締めくくり、良い睡眠につなげる", type: .night)
        context.insert(night)
        [
            ("スマホを充電場所に置く", 1),
            ("明日の予定を見る", 3),
            ("歯を磨く", 3),
            ("部屋の明かりを落とす", 1),
            ("ベッドに入る", 1),
        ].enumerated().forEach { index, item in
            let step = RoutineStep(
                title: item.0,
                orderIndex: index,
                estimatedMinutes: item.1,
                routine: night
            )
            context.insert(step)
        }
    }

    private static func seedBlockedBehaviorsIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<BlockedBehavior>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let samples: [(String, String, String)] = [
            ("起床直後にYouTubeを開く", "YouTube", "朝からYouTubeはダメ。まずはルーティン終わらせよ？"),
            ("起床直後にSNSを開く", "SNS", "SNSは後でいいでしょ。今やることあるよね？"),
            ("二度寝する", "二度寝", "気持ちは分かるけど、二度寝したら1日台無しだよ。"),
            ("深夜に動画を見続ける", "動画", "もう寝る時間。続きは明日の自分に任せよ。"),
        ]
        for (title, trigger, counter) in samples {
            let behavior = BlockedBehavior(
                title: title,
                triggerText: trigger,
                counterMessage: counter
            )
            context.insert(behavior)
        }
    }
}
