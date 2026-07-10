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
                    .foregroundStyle(.primary)
                }
            }

            Section("キャラクター名") {
                TextField("名前", text: $viewModel.name)
                TextField("説明", text: $viewModel.description, axis: .vertical)
            }

            Section("褒め方") {
                Picker("褒め方", selection: $viewModel.praiseStyle) {
                    ForEach(PraiseStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("叱り方") {
                Picker("叱り方", selection: $viewModel.scoldStyle) {
                    ForEach(ScoldStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("保存") {
                    viewModel.save()
                }
            }

            Section {
                SecureField("sk-...", text: $viewModel.openAIAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("APIキーを保存") {
                        viewModel.saveAPIKey()
                    }
                    Spacer()
                    Button("削除", role: .destructive) {
                        viewModel.clearAPIKey()
                    }
                }
            } header: {
                Text("OpenAI連携")
            } footer: {
                Text(viewModel.isUsingOpenAI
                     ? "APIキーが設定されているため、ChatGPT(Chat Completions API)で応答を生成します。"
                     : "APIキー未設定のため、ローカルテンプレートで応答します。")
            }

            Section {
                TextField("例: できた", text: $viewModel.completionPhrase)
                Button("保存") {
                    viewModel.saveCompletionPhrase()
                }
            } header: {
                Text("音声コマンド")
            } footer: {
                Text("音声会話中(またはテキスト入力)でこの発言をすると、現在のステップを完了として次に進みます。")
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
