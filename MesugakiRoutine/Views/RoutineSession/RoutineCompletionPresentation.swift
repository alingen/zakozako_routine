import SwiftUI

/// 完了演出に渡す表示データ。
struct RoutineCompletionContext: Identifiable, Equatable {
    let id = UUID()
    let routineTitle: String
    /// 完了後時点での、そのルーティンの連続達成回数。
    let currentStreak: Int
}

/// ルーティン完了時のシンプルな完了画面。チェック＋「◯◯ 完了！ N日達成」＋とじるボタンだけ。
struct RoutineCompletionPresentation: View {
    let context: RoutineCompletionContext
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
                    Text("\(context.currentStreak)日達成！")
                        .font(.headline)
                        .foregroundStyle(AppColor.success)
                }
            }

            Spacer()

            Button("とじる", action: onFinish)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

#Preview {
    RoutineCompletionPresentation(
        context: RoutineCompletionContext(routineTitle: "10分勉強する", currentStreak: 5),
        onFinish: {}
    )
}
