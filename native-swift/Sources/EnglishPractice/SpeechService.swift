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
    /// Human-readable diagnostics shown under the input bar.
    var statusMessage: String?
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

    nonisolated private static func askSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    nonisolated private static func askMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated private static func tapBlock(_ req: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in req.append(buffer) }
    }

    func requestAuthorization() async -> Bool {
        let speech = await Self.askSpeech()
        guard speech == .authorized else {
            authorizationDenied = true
            statusMessage = "Konuşma tanıma izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Konuşma Tanıma bölümünden English Practice'i aç."
            return false
        }
        guard await Self.askMic() else {
            authorizationDenied = true
            statusMessage = "Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon bölümünden English Practice'i aç."
            return false
        }
        authorizationDenied = false
        return true
    }

    func start(onFinal: @escaping ([SpokenWord]) -> Void) async {
        guard !isListening else { return }
        statusMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Konuşma tanıma şu an kullanılamıyor. İnternete bağlı mısın? Sistem Ayarları › Klavye › Dikte açık olmalı."
            return
        }
        guard await requestAuthorization() else { return }
        stopSpeaking()

        self.onFinal = onFinal
        liveTranscript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            statusMessage = "Mikrofon bulunamadı veya erişilemiyor (giriş cihazını Sistem Ayarları › Ses bölümünde kontrol et)."
            request = nil; self.onFinal = nil
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(req))
        engine.prepare()
        do { try engine.start() } catch {
            statusMessage = "Ses motoru başlatılamadı: \(error.localizedDescription)"
            input.removeTap(onBus: 0)
            request = nil; self.onFinal = nil
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let words = result?.bestTranscription.segments.map { SpokenWord(text: $0.substring, confidence: $0.confidence) } ?? []
            let errText = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.liveTranscript = text
                    self.armSilenceTimer()
                    if isFinal { self.finish(words: words) }
                } else if let errText {
                    self.fail(errText)
                }
            }
        }
    }

    private func fail(_ message: String) {
        let heard = !liveTranscript.isEmpty
        if heard {
            // Got some text before the error: deliver it.
            finish(words: liveTranscript.split(separator: " ").map { SpokenWord(text: String($0), confidence: 0) })
        } else {
            statusMessage = "Ses tanınamadı: \(message). Konuşmadıysan sorun yok; hata sürerse Sistem Ayarları › Klavye › Dikte'yi aç."
            finish(words: [])
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

    /// Waits longer when the sentence sounds unfinished (ends with "and", "because", "um"…) or is very short.
    private func silenceDelay() -> Double {
        let base = UserDefaults.standard.object(forKey: "silenceSeconds") as? Double ?? 2.0
        let words = liveTranscript.lowercased().split(separator: " ")
        let last = words.last.map(String.init) ?? ""
        let unfinished: Set<String> = ["and", "but", "because", "so", "or", "if", "when", "that", "with", "to", "the", "a", "an",
                                       "of", "in", "on", "at", "for", "um", "uh", "like", "then", "also", "my", "i", "is", "are", "was", "were", "have", "has"]
        var d = base
        if unfinished.contains(last) { d += 1.5 }
        if words.count < 3 { d += 0.7 }
        return d
    }

    private func armSilenceTimer() {
        silenceTask?.cancel()
        guard autoStop, !liveTranscript.isEmpty else { return }
        silenceTask = Task { [weak self] in
            let delay = self?.silenceDelay() ?? 2.0
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            self?.stop()
            // Don't wait for the recognizer's final pass: use the partial text if it is slow.
            try? await Task.sleep(for: .seconds(0.7))
            if Task.isCancelled { return }
            guard let self, self.isListening else { return }
            self.task?.cancel()
            self.finish(words: self.liveTranscript.split(separator: " ").map { SpokenWord(text: String($0), confidence: 0) })
        }
    }

    // MARK: Synthesis

    func speak(_ text: String, language: String = "en-US", rate: Float = 0.5) {
        stopSpeaking()
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language)
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        queued = 1
        isSpeaking = true
        synth.speak(u)
    }

    // Queued speech: sentences are enqueued while the LLM is still streaming.
    private var queued = 0
    private var holding = false

    func beginQueue() {
        stopSpeaking()
        holding = true
    }

    func enqueue(_ text: String, language: String = "en-US", rate: Float = 0.5) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: language)
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        queued += 1
        isSpeaking = true
        synth.speak(u)
    }

    /// Called when no more sentences will be enqueued. Fires `onSpeakFinished` once everything has been spoken.
    func endQueue() {
        holding = false
        if queued == 0 {
            isSpeaking = false
            onSpeakFinished?()
        }
    }

    func stopSpeaking() {
        queued = 0
        holding = false
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            self.queued = max(0, self.queued - 1)
            guard self.queued == 0 else { return }
            self.isSpeaking = false
            if !self.holding { self.onSpeakFinished?() }
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
