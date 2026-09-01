import SwiftUI

/// アイコン選択のスライドモーダル。選ぶと閉じる。
struct IconPickerView: View {
    let selected: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    cell(nil, systemImage: "nosign", label: "なし")
                    ForEach(RoutineIcon.all, id: \.self) { name in
                        cell(name, systemImage: name, label: name)
                    }
                }
                .padding(16)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("アイコンを選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func cell(_ name: String?, systemImage: String, label: String) -> some View {
        let isSelected = selected == name
        Button {
            onSelect(name)
            dismiss()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .frame(width: 52, height: 52)
                .foregroundStyle(isSelected ? Color.white : AppColor.text)
                .background(isSelected ? AppColor.primary : AppColor.surface, in: Circle())
                .overlay(Circle().stroke(AppColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
