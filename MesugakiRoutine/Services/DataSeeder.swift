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
        let defaults = CharacterPreset.makeDefault()
        let descriptor = FetchDescriptor<CharacterPreset>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if let current = existing.first(where: { $0.name == defaults.name }) {
            // basePromptはコード側で管理しているため、起動のたびに最新の内容へ同期する
            // (褒め方/叱り方などユーザーが設定画面で変更した項目はそのまま残す)。
            current.basePrompt = defaults.basePrompt
        } else {
            context.insert(defaults)
        }
    }

    private static func seedRoutinesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Routine>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let morning = Routine(title: "朝ルーティン", type: .morning, scheduledStartMinute: 7 * 60)
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

        let night = Routine(title: "夜ルーティン", type: .night, scheduledStartMinute: 22 * 60)
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

    /// 悪習慣は同時に1件しか挑戦できない設計のため、サンプルも1件だけ投入する。
    private static func seedBlockedBehaviorsIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<BlockedBehavior>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let behavior = BlockedBehavior(
            title: "YouTubeを見ない",
            triggerText: "YouTube",
            counterMessage: "朝からYouTubeはダメ。まずはルーティン終わらせよ？",
            reason: "仕事をさぼらないため",
            alternativeAction: "音楽をかけて仕事に戻る"
        )
        context.insert(behavior)
    }
}
