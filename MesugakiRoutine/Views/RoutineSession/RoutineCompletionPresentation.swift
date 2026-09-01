import SwiftUI

/// 完了体験(Presentation)に必要な表示データだけを持つ値型。ロジックは持たない。
/// SwiftData 保存 / Trust 更新 / EventUnlock は `RoutineCompletionService` 側で済ませ、
/// その結果(`RoutineCompletionResult`)＋履歴から呼び出し側がこれを組み立てて渡す。
struct RoutineCompletionContext: Identifiable, Equatable {
    let id = UUID()
    let routineTitle: String
    /// 完了後時点での、そのルーティンの連続達成回数。
    let currentStreak: Int
    /// この完了で信頼度が +1 されたか(同日2回目以降の完了なら false)。
    let trustAwarded: Bool
    /// 「今日の会話をはじめる」導線を出すか。
    /// - 多ステップ完了(RoutineSessionView 経由): 現状 true(従来どおり)
    /// - Home クイック完了: 現状 false
    /// - TODO(Step 6): 「今日のルーティンが全部完了した時だけ true」に統一する。
    let offersTodayConversation: Bool
}

/// ルーティン完了時にユーザーへ見せる「完了体験」。
///
/// このレイヤーは **表示とユーザー操作の受け取りだけ** を担当する。データ処理(保存・Trust・
/// EventUnlock)も、今日の会話画面への遷移も、このレイヤーはやらない。操作はコールバックで
/// 呼び出し側へ返すだけ。
///
/// 目的はザコルーティン独自の完了体験:
///   ルーティン完了 → 莉央が手を出す → ハイタッチ → 完了演出 → (必要なら)今日の会話
///
/// 現状はハイタッチ演出がまだ無いため、最小限の「通常完了画面」
/// (`StandardRoutineCompletionView`)を表示する。ハイタッチ演出ができたら、この `body` の
/// 中身を差し替えるだけで 通常完了画面 → ハイタッチ画面 に切り替えられる。
struct RoutineCompletionPresentation: View {
    let context: RoutineCompletionContext
    /// 「今日の会話をはじめる」を選んだとき(`context.offersTodayConversation == true` のときのみ表示)。
    var onStartTodayConversation: () -> Void
    /// 完了体験を閉じるとき(「今日は終わる」/「とじる」)。
    var onFinish: () -> Void

    var body: some View {
        // ▼ 差し替えポイント: 将来ここを HighFiveCompletionView(...) に置き換える。
        //   ハイタッチ演出の完了後に onStartTodayConversation / onFinish を呼ぶこと。
        StandardRoutineCompletionView(
            context: context,
            onStartTodayConversation: onStartTodayConversation,
            onFinish: onFinish
        )
    }
}

/// 現時点の「通常完了画面」。ハイタッチ演出ができるまでの暫定表示。
private struct StandardRoutineCompletionView: View {
    let context: RoutineCompletionContext
    var onStartTodayConversation: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColor.primarySoft)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(AppColor.primary)
            }

            VStack(spacing: 8) {
                Text("\(context.routineTitle) 完了！")
                    .font(.title2.bold())
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)

                if context.currentStreak >= 1 {
                    Text("\(context.currentStreak)日継続中！")
                        .font(.headline)
                        .foregroundStyle(AppColor.success)
                }

                if context.trustAwarded {
                    Text("信頼度 +1")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondary)
                }
            }

            // TODO(ハイタッチ): ここに「莉央が手を出す → ユーザーがタップでハイタッチ」の
            //   インタラクションが入る。現状は静的な完了表示のみ。

            Spacer()

            VStack(spacing: 12) {
                if context.offersTodayConversation {
                    Button("今日の会話をはじめる", action: onStartTodayConversation)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("今日は終わる", action: onFinish)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("とじる", action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

#Preview("継続あり・Trust加算・今日の会話あり") {
    RoutineCompletionPresentation(
        context: RoutineCompletionContext(
            routineTitle: "10分勉強する",
            currentStreak: 5,
            trustAwarded: true,
            offersTodayConversation: true
        ),
        onStartTodayConversation: {},
        onFinish: {}
    )
}

#Preview("クイック完了(今日の会話なし)") {
    RoutineCompletionPresentation(
        context: RoutineCompletionContext(
            routineTitle: "散歩する",
            currentStreak: 1,
            trustAwarded: false,
            offersTodayConversation: false
        ),
        onStartTodayConversation: {},
        onFinish: {}
    )
}
