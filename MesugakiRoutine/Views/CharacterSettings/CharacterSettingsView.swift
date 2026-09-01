import SwiftUI

struct CharacterSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CharacterSettingsViewModel()

    var body: some View {
        Form {
            Section("プリセット選択") {
                ForEach(viewModel.presets) { preset in
                    Button {
                        viewModel.selectPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if preset.isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(AppColor.text)
                }
                if let selected = viewModel.selectedPreset, !selected.presetDescription.isEmpty {
                    Text(selected.presetDescription)
                        .font(.footnote)
                        .foregroundStyle(AppColor.muted)
                }
            }

            Section("褒め方") {
                Picker("褒め方", selection: $viewModel.praiseStyle) {
                    ForEach(PraiseStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.praiseStyle) {
                    viewModel.save()
                }
            }

            Section("叱り方") {
                Picker("叱り方", selection: $viewModel.scoldStyle) {
                    ForEach(ScoldStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.scoldStyle) {
                    viewModel.save()
                }
            }
        }
        .navigationTitle("キャラクター設定")
        .task {
            viewModel.configure(context: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        CharacterSettingsView()
    }
    .modelContainer(for: [CharacterPreset.self], inMemory: true)
}
