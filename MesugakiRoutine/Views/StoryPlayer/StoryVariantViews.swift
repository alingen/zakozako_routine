import AVFoundation
import Combine
import SwiftUI

private extension StoryNode {
    var storyDisplayText: String {
        let direct = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !direct.isEmpty { return direct }
        let commandText = commandArgs?["text"]?.stringValue
        return commandText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var storyDisplaySpeakerName: String? {
        guard let value = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct StoryTitleCardView: View {
    let node: StoryNode

    var body: some View {
        Text(node.storyDisplayText)
            .font(.title.bold())
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.72))
            .accessibilityAddTraits(.isHeader)
    }
}

struct StoryNarrationView: View {
    let node: StoryNode

    var body: some View {
        Text(node.storyDisplayText)
            .font(.body)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("地の文。\(node.storyDisplayText)")
    }
}

struct StoryDialogueView: View {
    let node: StoryNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let speakerName = node.storyDisplaySpeakerName {
                Text(speakerName)
                    .font(.caption.bold())
                    .foregroundStyle(AppColor.primary)
            }

            Text(node.storyDisplayText)
                .font(.body)
                .foregroundStyle(AppColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StorySceneTransitionView: View {
    let node: StoryNode

    private var label: String {
        if !node.storyDisplayText.isEmpty {
            return node.storyDisplayText
        }
        return node.commandArgs?["label"]?.stringValue ?? "場面転換"
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(height: 1)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(height: 1)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("場面転換。\(label)")
    }
}

struct StoryMonologueView: View {
    let node: StoryNode

    var body: some View {
        Text(node.storyDisplayText)
            .font(.body.italic())
            .foregroundStyle(AppColor.text)
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.primarySoft.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("心の声。\(node.storyDisplayText)")
    }
}

struct StoryTypingView: View {
    let node: StoryNode

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let highlightedIndex = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == highlightedIndex ? AppColor.primary : AppColor.muted.opacity(0.4))
                            .frame(width: 7, height: 7)
                            .scaleEffect(index == highlightedIndex ? 1.2 : 0.85)
                    }
                }
            }

            if !node.storyDisplayText.isEmpty {
                Text(node.storyDisplayText)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppColor.surface, in: Capsule())
        .overlay(Capsule().stroke(AppColor.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.storyDisplayText.isEmpty ? "入力中" : "\(node.storyDisplayText)、入力中")
    }
}

private final class StoryAudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var loadedURL: URL?

    func toggle(url: URL) {
        if loadedURL == url, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                isPlaying = player.play()
            }
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            loadedURL = url
            errorMessage = nil
            isPlaying = player.play()
        } catch {
            player = nil
            loadedURL = nil
            isPlaying = false
            errorMessage = "音声を再生できません"
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

struct StoryAudioMessageView: View {
    let node: StoryNode
    @StateObject private var playback = StoryAudioPlaybackController()

    private var assetID: String? {
        guard let value = node.assetId?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var audioURL: URL? {
        guard let assetID else { return nil }
        if let exact = Bundle.main.url(forResource: assetID, withExtension: nil) {
            return exact
        }

        let sourceURL = URL(fileURLWithPath: assetID)
        let resourceName = sourceURL.deletingPathExtension().lastPathComponent
        let providedExtension = sourceURL.pathExtension
        if !providedExtension.isEmpty,
           let matched = Bundle.main.url(forResource: resourceName, withExtension: providedExtension) {
            return matched
        }

        for fileExtension in ["m4a", "mp3", "wav", "caf", "aac"] {
            if let matched = Bundle.main.url(forResource: assetID, withExtension: fileExtension) {
                return matched
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    guard let audioURL else { return }
                    playback.toggle(url: audioURL)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(audioURL == nil ? AppColor.muted : AppColor.primary, in: Circle())
                }
                .disabled(audioURL == nil)
                .accessibilityLabel(playback.isPlaying ? "音声を一時停止" : "音声を再生")
                .accessibilityHint(audioURL == nil ? "音声素材が見つかりません" : "")

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.storyDisplayText.isEmpty ? "音声メッセージ" : node.storyDisplayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    Text(assetID ?? "asset未指定")
                        .font(.caption2.monospaced())
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(2)
                }
            }

            if audioURL == nil {
                Label("音声素材が見つかりません", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppColor.warning)
            } else if let errorMessage = playback.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppColor.error)
            }
        }
        .padding(14)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColor.border)
        }
        .onDisappear { playback.stop() }
    }
}

struct StoryImageMessageView: View {
    let node: StoryNode

    private var displayedAssetID: String? {
        node.assetId ?? node.cg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StoryAssetView(
                assetID: displayedAssetID,
                purpose: node.cg == nil ? .image : .cg,
                contentMode: .fit,
                cornerRadius: 14
            )
            .frame(maxWidth: 280, minHeight: 160, maxHeight: 320)

            if !node.storyDisplayText.isEmpty {
                Text(node.storyDisplayText)
                    .font(.caption)
                    .foregroundStyle(AppColor.text)
            }
        }
        .padding(10)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColor.border)
        }
    }
}

struct StoryChoicePanel: View {
    let choices: [StoryChoice]
    var isEnabled = true
    let onSelect: (StoryChoice) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(choices.sorted { $0.choiceOrder < $1.choiceOrder }) { choice in
                Button {
                    onSelect(choice)
                } label: {
                    HStack(spacing: 10) {
                        Text(choice.label)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(AppColor.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColor.primary, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.55)
                .accessibilityLabel("選択肢。\(choice.label)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("選択肢")
    }
}

struct StoryModalView: View {
    let node: StoryNode
    var buttonTitle = "閉じる"
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(AppColor.secondary)

            Text(node.storyDisplayText)
                .font(.body)
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(buttonTitle, action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(AppColor.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppColor.border)
        }
        .shadow(color: AppColor.text.opacity(0.14), radius: 24, y: 8)
        .padding(28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("メッセージ")
    }
}

struct StoryUnknownVariantView: View {
    let node: StoryNode
    let variant: StoryUIVariant?

    private var variantName: String {
        guard let rawValue = variant?.rawValue, !rawValue.isEmpty else { return "未指定" }
        return rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("未対応の表示: \(variantName)", systemImage: "questionmark.diamond")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.warning)

            if !node.storyDisplayText.isEmpty {
                Text(node.storyDisplayText)
                    .font(.body)
                    .foregroundStyle(AppColor.text)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColor.warning.opacity(0.55))
        }
        .accessibilityElement(children: .combine)
    }
}
