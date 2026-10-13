import Foundation
import Speech
import AVFoundation
import Observation

/// Speech-to-text (on-device when available, with per-word confidence) and text-to-speech.
@MainActor
@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    var isListening = false
    var liveTranscript = ""
    var authorizationDenied = false
    /// When true, listening stops by itself after a short silence (hands-free mode).
    var autoStop = false
    var onSpeakFinished: (() -> Void)?
    private var silenceTask: Task<Void, Never>?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: (([SpokenWord]) -> Void)?

    private let synth = AVSpeechSynthesizer()
    var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: Recognition

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        authorizationDenied = !(speech && mic)
        return speech && mic
    }

    func start(onFinal: @escaping ([SpokenWord]) -> Void) async {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        guard await requestAuthorization() else { return }
        stopSpeaking()

        self.onFinal = onFinal
        liveTranscript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buf, _ in req?.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { return }
        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    self.armSilenceTimer()
                    if result.isFinal {
                        let words = result.bestTranscription.segments.map {
                            SpokenWord(text: $0.substring, confidence: $0.confidence)
                        }
                        self.finish(words: words)
                    }
                } else if error != nil {
                    self.finish(words: self.liveTranscript.split(separator: " ").map { SpokenWord(text: String($0), confidence: 0) })
                }
            }
        }
    }

    /// Ends audio capture; the recognizer then delivers the final result.
    func stop() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func finish(words: [SpokenWord]) {
        guard isListening else { return }
        isListening = false
        silenceTask?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task = nil
        request = nil
        let cb = onFinal
        onFinal = nil
        cb?(words)
    }

    private func armSilenceTimer() {
        silenceTask?.cancel()
        guard autoStop, !liveTranscript.isEmpty else { return }
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            if !Task.isCancelled { self?.stop() }
        }
    }

    // MARK: Synthesis

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.5) {
        stopSpeaking()
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language)
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        isSpeaking = true
        synth.speak(u)
    }

    func stopSpeaking() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onSpeakFinished?()
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
