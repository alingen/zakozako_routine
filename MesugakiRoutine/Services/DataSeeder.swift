import SwiftData

/// アプリの初期データ投入をまとめる入口。
@MainActor
enum DataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        // 最初の約束はオンボーディングでユーザー自身が作る。
        // サンプル Routine は投入せず、空の状態を保つ。
        try? context.save()
    }
}
