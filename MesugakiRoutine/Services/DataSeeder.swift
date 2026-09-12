import Foundation
import SwiftData

/// 初回起動時に、操作例になるシンプルなルーティンを投入する。
@MainActor
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        seedRoutinesIfNeeded(context: context)
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

}
