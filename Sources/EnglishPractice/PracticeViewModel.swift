import Foundation
import Observation

@MainActor
@Observable
final class PracticeViewModel {
    var items: [ChatItem] = [
        ChatItem(role: .assistant, text: "Hi! I'm your English practice partner. Tell me about your day — type or press the mic.")
    ]
    var draft = ""
    var pendingWords: [SpokenWord] = []
    var isBusy = false
    var errorMessage: String?
    var voiceMode = false
    var ollamaStatus: OllamaStatus = .unknown
    private var store: DataStore?

    let speech = SpeechService()

    var client: OllamaClient {
        let d = UserDefaults.standard
        return OllamaClient(host: d.string(forKey: "ollamaHost") ?? "http://localhost:11434",
                            model: d.string(forKey: "ollamaModel") ?? "gemma3:4b")
    }
    var autoSpeak: Bool { UserDefaults.standard.object(forKey: "autoSpeak") as? Bool ?? true }
    var speechRate: Float { Float(UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 0.5) }

    private let chatSystem = """
    You are a friendly English conversation partner for a Turkish-speaking learner. \
    Reply in 1-2 short, simple sentences, then ask one short question. Never correct or comment on grammar. No lists, no emojis.
    """

    private let correctionSystem = """
    You check English sentences written by a Turkish-speaking learner. Return JSON with:
    - corrected: the sentence rewritten with correct grammar (identical if already correct).
    - errors: each distinct mistake. category must be one of the allowed values; original and fixed are the minimal wrong/right fragments; explanation is one short sentence in Turkish.
    Do not invent errors. Ignore capitalization and punctuation style unless clearly wrong. If the sentence is correct, errors is an empty array.
    """

    func toggleMic() async {
        if speech.isListening {
            speech.stop()
        } else {
            await speech.start { [weak self] words in
                guard let self else { return }
                self.pendingWords = words
                self.draft = words.map(\.text).joined(separator: " ")
                if self.voiceMode, let store = self.store, !self.draft.isEmpty {
                    Task { await self.send(store: store) }
                }
            }
        }
    }

    /// Hands-free conversation: listen → send → speak reply → listen again.
    func setVoiceMode(_ on: Bool, store: DataStore) {
        voiceMode = on
        speech.autoStop = on
        if on {
            self.store = store
            speech.onSpeakFinished = { [weak self] in
                guard let self, self.voiceMode, !self.speech.isListening else { return }
                Task { await self.toggleMic() }
            }
            if !speech.isListening { Task { await toggleMic() } }
        } else {
            speech.onSpeakFinished = nil
            if speech.isListening { speech.stop() }
        }
    }

    func refreshStatus() async {
        let c = client
        do {
            let installed = try await c.models()
            if installed.contains(c.model) || installed.contains(c.model + ":latest") { ollamaStatus = .ready; Task { await c.warmUp() } }
            else { ollamaStatus = .modelMissing(installed) }
        } catch { ollamaStatus = .down }
    }

    func send(store: DataStore) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        let words = pendingWords
        draft = ""
        pendingWords = []
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        store.recordActivity()
        let userItem = ChatItem(role: .user, text: text, words: words)

        // History for the reply (before adding the new items).
        var messages = [OllamaMessage(role: "system", content: chatSystem)]
        for item in items.suffix(7) {
            messages.append(OllamaMessage(role: item.role == .user ? "user" : "assistant", content: item.text))
        }
        messages.append(OllamaMessage(role: "user", content: text))

        items.append(userItem)
        let replyItem = ChatItem(role: .assistant, text: "")
        items.append(replyItem)

        for w in words where w.isWeak {
            store.add(Mistake(category: ErrorCategory.pronunciation.rawValue, original: w.text.lowercased(),
                              fixed: w.text.lowercased(), explanation: "Bu kelimeyi net söyleyemedin."))
        }

        let speak = autoSpeak || voiceMode
        let rate = speechRate
        if speak { speech.beginQueue() }
        var buffer = ""
        do {
            for try await chunk in client.stream(messages) {
                append(chunk, to: replyItem.id)
                if speak {
                    buffer += chunk
                    for sentence in Self.drainSentences(&buffer, final: false) { speech.enqueue(sentence, rate: rate) }
                }
            }
            if speak {
                for sentence in Self.drainSentences(&buffer, final: true) { speech.enqueue(sentence, rate: rate) }
                if !buffer.isEmpty { speech.enqueue(buffer, rate: rate) }
                speech.endQueue()
            }
        } catch {
            errorMessage = error.localizedDescription
            if let idx = items.firstIndex(where: { $0.id == replyItem.id }), items[idx].text.isEmpty { items.remove(at: idx) }
            if speak { speech.endQueue() }
            if voiceMode { voiceMode = false; speech.autoStop = false; speech.onSpeakFinished = nil }
            return
        }

        // Grammar check runs after the reply is already on screen / being spoken.
        let c = client
        let userID = userItem.id
        Task { [weak self] in
            let msgs = [OllamaMessage(role: "system", content: self?.correctionSystem ?? ""),
                        OllamaMessage(role: "user", content: text)]
            guard let result = try? await c.decode(Correction.self, messages: msgs, schema: Schemas.correction,
                                                   temperature: 0.1, numPredict: 300) else { return }
            guard let self else { return }
            if let idx = self.items.firstIndex(where: { $0.id == userID }) {
                self.items[idx].corrected = result.corrected.trimmingCharacters(in: .whitespacesAndNewlines) == text ? nil : result.corrected
                self.items[idx].errors = result.errors
            }
            for e in result.errors {
                store.add(Mistake(category: e.category, original: e.original, fixed: e.fixed, explanation: e.explanation))
            }
        }
    }

    private func append(_ chunk: String, to id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) { items[idx].text += chunk }
    }

    /// Splits off completed sentences from `buffer`; with `final` the trailing sentence is flushed too.
    nonisolated static func drainSentences(_ buffer: inout String, final: Bool) -> [String] {
        var sentences: [String] = []
        var start = buffer.startIndex
        var i = buffer.startIndex
        while i < buffer.endIndex {
            if ".!?".contains(buffer[i]) {
                let n = buffer.index(after: i)
                if n == buffer.endIndex {
                    if final { sentences.append(String(buffer[start..<n])); start = n }
                    break
                }
                if buffer[n].isWhitespace { sentences.append(String(buffer[start..<n])); start = n }
            }
            i = buffer.index(after: i)
        }
        buffer = String(buffer[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentences
    }

    /// Short status for hands-free mode.
    var voiceStatus: String? {
        guard voiceMode else { return nil }
        if speech.isListening { return "🎙 Dinliyorum…" }
        if isBusy { return "⏳ Düşünüyor…" }
        if speech.isSpeaking { return "🔊 Konuşuyor…" }
        return "…"
    }
}

enum OllamaStatus {
    case unknown, ready, down
    case modelMissing([String])
}
