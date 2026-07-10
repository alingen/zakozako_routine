import Foundation
import Speech
import AVFoundation

/// アプリ起動直後などに「数秒だけ音声コマンドを受け付ける」ための一回限りのリスナー。
///
/// `NativeVoiceConversationEngine` は「聞く→考える→話す」を繰り返す持続セッション用だが、
/// こちらは「起動時に一言だけ聞いて、タイムアウトしたら諦める」という別のライフサイクルのため、
/// あえて別クラスにしている(会話継続やTTSの読み上げは行わない)。
@MainActor
final class QuickVoiceCommandListener {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((String?) -> Void)?

    /// `timeout` 秒以内に発話が確定しなければ nil を返す。許可が無い・認識できない場合も nil を返す
    /// (エラーとして表に出す必要のない、ベストエフォートな機能のため)。
    func listenOnce(timeout: TimeInterval = 6) async -> String? {
        await withCheckedContinuation { continuation in
            self.completion = { text in
                continuation.resume(returning: text)
            }
            Task {
                do {
                    try await self.requestPermissions()
                    guard let recognizer = self.speechRecognizer, recognizer.isAvailable else {
                        self.finish(with: nil)
                        return
                    }
                    try self.configureAudioSession()
                    try self.startListening()
                    self.scheduleTimeout(timeout)
                } catch {
                    self.finish(with: nil)
                }
            }
        }
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { throw CancellationError() }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else { throw CancellationError() }
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
    }

    private func scheduleTimeout(_ seconds: TimeInterval) {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(with: nil)
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result, result.isFinal else { return }
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(with: text.isEmpty ? nil : text)
    }

    private func finish(with text: String?) {
        guard let callback = completion else { return }
        completion = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        stopListening()
        callback(text)
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
