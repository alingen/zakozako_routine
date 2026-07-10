import Foundation
import Speech
import AVFoundation

/// Apple標準の音声認識(Speech framework)と音声合成(AVSpeechSynthesizer)を組み合わせた
/// `VoiceConversationEngine` の暫定実装。
///
/// 「聞く→(既存の ConversationCoordinator に投げて)考える→話す」を繰り返すだけの構成。
/// OpenAI Realtime API は音声認識・思考・音声合成を1つのストリーミングセッションで一体的に行うため、
/// 将来そちらへ差し替える際は本クラスをまるごと `OpenAIRealtimeVoiceConversationEngine` に
/// 置き換えるだけでよい(呼び出し側は `VoiceConversationEngine` protocol しか見ていない)。
///
/// 声の自然さはAVSpeechSynthesizer標準ボイス相応であり、Realtime API ほどの「リアルさ」は出ない。
/// あくまで音声対話ループの動作確認・土台として位置づける。
@MainActor
final class NativeVoiceConversationEngine: NSObject, VoiceConversationEngine {
    enum VoiceEngineError: LocalizedError {
        case permissionDenied
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "マイク/音声認識の使用が許可されていません。"
            case .recognizerUnavailable: return "この端末・言語では音声認識が利用できません。"
            }
        }
    }

    weak var delegate: VoiceConversationDelegate?

    private(set) var state: VoiceConversationState = .idle {
        didSet { delegate?.voiceConversation(self, didChangeState: state) }
    }

    /// ユーザーの発話テキストを受け取り、キャラクターの返答テキストを返すクロージャ。
    /// 実体は `ConversationCoordinator.submitFreeText` を想定している。
    private let onUserUtterance: (String) async -> String

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    /// 発話が止まってから確定とみなすまでの無音時間。
    private let silenceTimeout: TimeInterval = 1.2
    private var silenceTimer: Timer?
    private var lastTranscript = ""

    init(onUserUtterance: @escaping (String) async -> String) {
        self.onUserUtterance = onUserUtterance
        super.init()
        synthesizer.delegate = self
    }

    func start() async throws {
        guard state == .idle else { return }
        try await requestPermissions()
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceEngineError.recognizerUnavailable
        }
        try configureAudioSession()
        try startListening()
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }

    func speak(_ text: String) {
        guard state != .idle else { return }
        stopListening()
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        synthesizer.speak(utterance)
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { throw VoiceEngineError.permissionDenied }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else { throw VoiceEngineError.permissionDenied }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startListening() throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
        lastTranscript = ""
        state = .listening
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result else { return }
        let text = result.bestTranscription.formattedString
        delegate?.voiceConversation(self, didUpdatePartialUserText: text)
        if text != lastTranscript {
            lastTranscript = text
            resetSilenceTimer()
        }
        if result.isFinal {
            finalizeTurn(text: text)
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recognitionRequest?.endAudio()
            }
        }
    }

    private func finalizeTurn(text: String) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resumeListening()
            return
        }
        stopListening()
        state = .thinking
        delegate?.voiceConversation(self, didRecognizeFinalUserText: trimmed)

        Task {
            let reply = await onUserUtterance(trimmed)
            delegate?.voiceConversation(self, didReceiveCharacterText: reply)
            speak(reply)
        }
    }

    private func resumeListening() {
        do {
            try startListening()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

extension NativeVoiceConversationEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleSpeechFinished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleSpeechFinished() }
    }

    private func handleSpeechFinished() {
        guard state == .speaking else { return }
        resumeListening()
    }
}
