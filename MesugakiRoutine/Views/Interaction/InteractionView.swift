import SwiftUI

/// 「交流」タブ。キャラクターと触れ合う場所。中身は今後実装する(現状はプレースホルダ)。
struct InteractionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.primary)
            Text("交流")
                .font(.title3.bold())
                .foregroundStyle(AppColor.text)
            Text("キャラクターと触れ合える機能は準備中です。")
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("交流")
    }
}

#Preview {
    NavigationStack {
        InteractionView()
    }
}
