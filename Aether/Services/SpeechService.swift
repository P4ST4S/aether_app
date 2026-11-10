import AVFoundation
import Foundation
import Observation
import Speech

// The audio callback and UI stop path share a request; serialize append/endAudio.
private final class RecognitionInput: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var ended = false
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return 0 }
        request.append(buffer)
        guard let samples = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in stride(from: 0, to: Int(buffer.frameLength), by: 8) { sum += abs(samples[index]) }
        return min(1, Double(sum / Float(max(1, buffer.frameLength / 8))) * 12)
    }
    func end() {
        lock.lock()
        defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        request.endAudio()
    }
}

@MainActor @Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var input: RecognitionInput?
    private var tapInstalled = false
    private var sessionID: UUID?
    var isListening = false
    var isRequestingPermissions = false
    var isSpeaking = false
    var audioLevel = 0.0
    var errorMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startListening(onTranscript: @escaping @MainActor (String) -> Void) async {
        stopAll()
        errorMessage = nil
        let id = UUID()
        sessionID = id
        isRequestingPermissions = true
        defer { if sessionID == id { isRequestingPermissions = false } }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device dictation is unavailable for \(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier). Use text input or install speech assets in macOS Settings."
            return
        }
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == id else { return }
        guard speechPermission == .authorized else {
            errorMessage = "Allow Speech Recognition for Aether in System Settings → Privacy & Security to use dictation."
            return
        }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard sessionID == id else { return }
        guard microphoneAllowed else {
            errorMessage = "Allow Microphone access for Aether in System Settings → Privacy & Security. Text chat is still available."
            return
        }
        guard recognizer.isAvailable else {
            errorMessage = "On-device recognition is currently unavailable. Try again later or use text input."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let input = RecognitionInput(request)
        self.input = input
        self.recognizer = recognizer
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No working microphone was found. Check your macOS input device."
            stopListening()
            return
        }
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            let level = input.append(buffer)
            Task { @MainActor in
                guard self?.sessionID == id else { return }
                self?.audioLevel = level
            }
        }
        tapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                if let transcript { onTranscript(transcript) }
                if let failure { self.errorMessage = "Dictation stopped: \(failure)" }
                if final || failure != nil { self.stopListening() }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isListening = true
        } catch {
            errorMessage = "The microphone could not start: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        sessionID = nil
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        input?.end()
        input = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        isListening = false
        isRequestingPermissions = false
        audioLevel = 0
    }

    func stopAll() {
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speak(_ text: String) {
        stopAll()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        }
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
