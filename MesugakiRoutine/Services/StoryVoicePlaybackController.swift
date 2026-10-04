import AVFoundation
import Observation
import SwiftUI

@MainActor
protocol StoryVoiceAudioPlayer: AnyObject {
    var onCompletion: (() -> Void)? { get set }
    func play() -> Bool
    func stop()
}

@MainActor
private final class AVStoryVoiceAudioPlayer: NSObject, StoryVoiceAudioPlayer, AVAudioPlayerDelegate {
    var onCompletion: (() -> Void)?
    private let player: AVAudioPlayer

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    func play() -> Bool {
        do {
            // Match the existing BGM/SE session so voice does not interrupt them.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            player.prepareToPlay()
            return player.play()
        } catch { return false }
    }

    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }
}

/// One voice per displayed line. Independent of BGM, SE and chat audio messages.
@MainActor
@Observable
final class StoryVoicePlaybackController {
    private(set) var selectedNodeID: String?
    private(set) var hasAttemptedPlayback = false
    private(set) var isPlaying = false
    private(set) var diagnostic: String?
    @ObservationIgnored private var player: (any StoryVoiceAudioPlayer)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let resolveURL: (StoryNode) -> URL?
    @ObservationIgnored private let makePlayer: @MainActor (URL) throws -> any StoryVoiceAudioPlayer

    init(
        resolveURL: @escaping (StoryNode) -> URL? = { StoryVoiceResource.url(for: $0) },
        makePlayer: @escaping @MainActor (URL) throws -> any StoryVoiceAudioPlayer = { try AVStoryVoiceAudioPlayer(url: $0) }
    ) {
        self.resolveURL = resolveURL
        self.makePlayer = makePlayer
    }

    func select(nodeID: String?) {
        guard selectedNodeID != nodeID else { return }
        stop()
        selectedNodeID = nodeID
        hasAttemptedPlayback = false
        diagnostic = nil
    }

    /// Called by the text window at its first character, not when the scene loads.
    func start(node: StoryNode) {
        select(nodeID: node.nodeId)
        guard !hasAttemptedPlayback else { return }
        hasAttemptedPlayback = true
        guard StoryVoiceResource.hasVoice(node) else { return }
        guard let url = resolveURL(node) else {
            diagnostic = "ボイス素材が見つかりません: \(node.voiceAssetId ?? "")"
            return
        }
        do {
            let audio = try makePlayer(url)
            let token = generation
            audio.onCompletion = { [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
            }
            player = audio
            isPlaying = audio.play()
            if !isPlaying {
                diagnostic = "ボイスを再生できません: \(node.voiceAssetId ?? "")"
                stop()
            }
        } catch {
            diagnostic = "ボイスを再生できません: \(node.voiceAssetId ?? "")"
            stop()
        }
    }

    /// Fast-forward consumes the line's voice without playing or restarting it.
    func suppress(nodeID: String?) {
        select(nodeID: nodeID)
        hasAttemptedPlayback = true
        stop()
    }

    func stop() {
        generation += 1
        player?.onCompletion = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    func awaitsCompletion(for node: StoryNode) -> Bool {
        guard StoryVoiceResource.hasVoice(node) else { return false }
        return selectedNodeID != node.nodeId || !hasAttemptedPlayback || isPlaying
    }
}

enum StoryVoiceResource {
    static func hasVoice(_ node: StoryNode) -> Bool {
        !(node.voiceAssetId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func url(for node: StoryNode, bundle: Bundle = .main) -> URL? {
        guard hasVoice(node) else { return nil }
        let name = [node.voiceFileName, node.voiceAssetId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        // Bundle resources only; never fetch arbitrary URLs or read outside it.
        let path = name as NSString
        guard !path.isAbsolutePath, !path.pathComponents.contains(".."),
              !name.contains("://") else { return nil }
        let resource = URL(fileURLWithPath: name)
        let stem = resource.deletingPathExtension().lastPathComponent
        let directory = path.deletingLastPathComponent
        let folders: [String?] = directory.isEmpty ? [nil, "Audio"] : [directory, nil]
        let extensions = resource.pathExtension.isEmpty
            ? ["m4a", "mp3", "wav", "caf", "aac"] : [resource.pathExtension]
        for folder in folders {
            for fileExtension in extensions {
                if let url = bundle.url(forResource: stem, withExtension: fileExtension, subdirectory: folder) {
                    return url
                }
            }
        }
        return nil
    }
}

private struct StoryVoicePlaybackKey: EnvironmentKey {
    static let defaultValue: StoryVoicePlaybackController? = nil
}

extension EnvironmentValues {
    var storyVoicePlayback: StoryVoicePlaybackController? {
        get { self[StoryVoicePlaybackKey.self] }
        set { self[StoryVoicePlaybackKey.self] = newValue }
    }
}
