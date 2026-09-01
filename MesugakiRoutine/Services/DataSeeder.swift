import Foundation
import SwiftData

/// 初回起動時にサンプルデータ(シンプルなルーティン数件、やらないこと1件、デフォルトキャラ)を投入する。
/// 既存ユーザー(すでにデータがある)には一切触れない。
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

    /// 新規ユーザー向けに、朝/夜という分類を前提にしないシンプルなルーティンを数件だけ投入する。
    /// 種別は内部的に `.custom` 固定、開始予定時刻なし、対象は毎日。
    private static func seedRoutinesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Routine>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let samples: [(title: String, steps: [String])] = [
            ("10分勉強する", ["10分だけ机に向かう"]),
            ("散歩する", ["外に出て歩く"]),
        ]

        for sample in samples {
            let routine = Routine(title: sample.title, type: .custom)
            context.insert(routine)
            for (index, stepTitle) in sample.steps.enumerated() {
                context.insert(
                    RoutineStep(title: stepTitle, orderIndex: index, routine: routine)
                )
            }
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
