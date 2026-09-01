import SwiftUI

extension View {
    /// グループ化 List / Form の地色をアプリ背景色(AppColor.background)に差し替える。
    /// 併せて各 Section / 行には `.listRowBackground(AppColor.surface)` を付ける。
    func appScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppColor.background.ignoresSafeArea())
    }

    /// カード風の行の地色。`appScreenBackground()` で地色を消した List / Form の行に付ける。
    func appCardRow() -> some View {
        listRowBackground(AppColor.surface)
    }
}
