import Foundation
import SwiftData

/// 初回起動時にサンプルデータ(シンプルなルーティン数件、やらないこと1件)を投入する。
/// 既存ユーザー(すでにデータがある)には一切触れない。
@MainActor
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        seedRoutinesIfNeeded(context: context)
        seedBlockedBehaviorsIfNeeded(context: context)
        try? context.save()
    }

    /// 新規ユーザー向けに、シンプルなルーティンを数件だけ投入する。
    /// 開始予定時刻なし、対象は毎日。
    private static func seedRoutinesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Routine>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let samples: [(title: String, icon: String)] = [
            ("10分勉強する", "book"),
            ("散歩する", "figure.walk"),
        ]
        for sample in samples {
            context.insert(Routine(title: sample.title, iconName: sample.icon))
        }
    }

    /// 「やらないこと」は同時に1件しか挑戦できない設計のため、サンプルも1件だけ投入する。
    private static func seedBlockedBehaviorsIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<BlockedBehavior>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        context.insert(BlockedBehavior(title: "YouTubeを見ない"))
    }
}
