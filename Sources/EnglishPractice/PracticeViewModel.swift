import Foundation
import Observation

enum OllamaStatus {
    case unknown, ready, down
    case modelMissing([String])
    case needsKey
}

@MainActor
@Observable
final class PracticeViewModel {
    var items: [ChatItem] = []
    var draft = ""
    var pendingWords: [SpokenWord] = []
    var isBusy = false
    var errorMessage: String?
    var voiceMode = false
    var ollamaStatus: OllamaStatus = .unknown
    private var store: DataStore?
    private var prepared = false
    private var turnsSinceMemory = 0

    let speech = SpeechService()

    // MARK: Settings-backed values

    private var defaults: UserDefaults { .standard }
    var provider: String { defaults.string(forKey: "provider") ?? "ollama" }
    var level: String { defaults.string(forKey: "level") ?? "A2" }
    var autoSpeak: Bool { defaults.object(forKey: "autoSpeak") as? Bool ?? true }
    var speechRate: Float { Float(defaults.object(forKey: "speechRate") as? Double ?? 0.5) }

    var ollama: OllamaClient {
        OllamaClient(host: defaults.string(forKey: "ollamaHost") ?? "http://localhost:11434",
                     model: defaults.string(forKey: "ollamaModel") ?? "gemma3:4b")
    }

    /// The active backend: Claude API when selected and a key exists, otherwise local Ollama.
    var client: any LLMClient {
        if provider == "claude", let key = Keychain.get("anthropic"), !key.isEmpty { return ClaudeClient(apiKey: key) }
        return ollama
    }

    // MARK: Prompts

    private func chatSystem(store: DataStore) -> String {
        var s = """
        You are Parla, a warm, curious English conversation partner and coach for a Turkish-speaking learner (CEFR level \(level)).
        Your job: have a REAL conversation with them while quietly helping them improve.

        How to reply:
        - React to what they actually said: refer to a concrete detail from their message so they feel understood, then move the conversation forward.
        - 2-4 short sentences of natural spoken English suited to level \(level) (simpler words and shorter sentences for lower levels).
        - End with ONE specific follow-up question that makes them answer with a few sentences (prefer "why", "how", "what happened", "tell me about…" over yes/no).
        - Lead the conversation. If their answers are short or vague, ask for details or an example. If they are stuck or say they don't know, offer two concrete options or suggest a topic. Every few turns, give a small speaking challenge (describe something, compare two things, tell a short story, give and defend an opinion).
        - If they write in Turkish, answer in simple English and give the English version of what they meant.
        - Do not lecture or point out grammar mistakes (a separate checker does that). You may naturally reuse their sentence correctly in your reply.
        - Use what you remember about them when it fits, without listing facts. Sometimes ask a follow-up about something from earlier conversations.
        - No lists, no emojis, no markdown.
        """
        if !store.memory.isEmpty {
            s += "\n\nWhat you remember about the learner:\n" + store.memory.map { "- \($0)" }.joined(separator: "\n")
        }
        let weak = LessonGenerator.summarize(store.mistakes).filter { $0.kind != .pronunciation }.prefix(2).map(\.kind.rawValue)
        if !weak.isEmpty {
            s += "\n\nTheir most frequent mistake types: \(weak.joined(separator: ", ")). Without mentioning it, steer the topic so they get natural chances to use these (for example, ask about past events to practise past tense)."
        }
        return s
    }

    private let correctionSystem = """
    You check English sentences written by a Turkish-speaking learner. Return JSON with:
    - corrected: the sentence rewritten with correct grammar (identical if already correct).
    - errors: each distinct mistake. category must be one of the allowed values; original and fixed are the minimal wrong/right fragments; explanation is one short sentence in Turkish.
    Do not invent errors. Ignore capitalization and punctuation style unless clearly wrong. If the sentence is correct, errors is an empty array.
    """

    // MARK: Lifecycle

    /// Restores the previous conversation (or opens a new one that follows up on memory).
    func prepare(store: DataStore) async {
        guard !prepared else { return }
        prepared = true
        self.store = store
        if store.chat.isEmpty {
            await openConversation(store: store)
        } else {
            items = store.chat.suffix(30).map { ChatItem(role: $0.isUser ? .user : .assistant, text: $0.text) }
        }
    }

    func newConversation(store: DataStore) {
        speech.stopSpeaking()
        store.clearChat()
        items = []
        Task { await openConversation(store: store) }
    }

    private func openConversation(store: DataStore) async {
        let known = store.memory.isEmpty ? "You don't know anything about them yet, so ask for their name and what they do or enjoy."
                                         : "Greet them (use their name if you know it) and ask about something you remember about them."
        let messages = [
            OllamaMessage(role: "system", content: chatSystem(store: store)),
            OllamaMessage(role: "user", content: "[Start the conversation now. \(known) Keep it to 2 sentences and end with one question.]"),
        ]
        let item = ChatItem(role: .assistant, text: "")
        items.append(item)
        isBusy = true
        defer { isBusy = false }
        let speak = voiceMode
        if speak { speech.beginQueue() }
        var buffer = ""
        var full = ""
        do {
            for try await chunk in client.stream(messages, numPredict: 120, temperature: 0.8) {
                append(chunk, to: item.id)
                full += chunk
                if speak {
                    buffer += chunk
                    for s in Self.drainSentences(&buffer, final: false) { speech.enqueue(s, rate: speechRate) }
                }
            }
            if speak {
                for s in Self.drainSentences(&buffer, final: true) { speech.enqueue(s, rate: speechRate) }
                if !buffer.isEmpty { speech.enqueue(buffer, rate: speechRate) }
                speech.endQueue()
            }
            store.appendChat([StoredMessage(isUser: false, text: full)])
        } catch {
            if speak { speech.endQueue() }
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].text = "Hi! I'm Parla, your English practice partner. What's your name, and what do you like to do?"
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Microphone

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
            if !speech.isListening && !isBusy { Task { await toggleMic() } }
        } else {
            speech.onSpeakFinished = nil
            if speech.isListening { speech.stop() }
        }
    }

    func refreshStatus() async {
        if provider == "claude" {
            ollamaStatus = (Keychain.get("anthropic") ?? "").isEmpty ? .needsKey : .ready
            return
        }
        let c = ollama
        do {
            let installed = try await c.models()
            if installed.contains(c.model) || installed.contains(c.model + ":latest") {
                ollamaStatus = .ready
                Task { await c.warmUp() }
            } else { ollamaStatus = .modelMissing(installed) }
        } catch { ollamaStatus = .down }
    }

    // MARK: Sending

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

        var messages = [OllamaMessage(role: "system", content: chatSystem(store: store))]
        for item in items.suffix(14) where !item.text.isEmpty {
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
        var full = ""
        do {
            for try await chunk in client.stream(messages, numPredict: 220, temperature: 0.7) {
                append(chunk, to: replyItem.id)
                full += chunk
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

        store.appendChat([StoredMessage(isUser: true, text: text), StoredMessage(isUser: false, text: full)])

        let c = client
        let userID = userItem.id

        // Grammar check, after the reply is already on screen / being spoken.
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

        // Long-term memory: refresh the notes every few turns.
        turnsSinceMemory += 1
        if turnsSinceMemory >= 3 {
            turnsSinceMemory = 0
            let recent = store.chat.suffix(8).map { ($0.isUser ? "Learner: " : "Parla: ") + $0.text }.joined(separator: "\n")
            let existing = store.memory.map { "- \($0)" }.joined(separator: "\n")
            Task {
                let prompt = """
                Current notes about the learner:
                \(existing.isEmpty ? "(none)" : existing)

                Recent conversation:
                \(recent)

                Update the notes. Keep durable, useful facts only: name, job/studies, family, hobbies, places, goals, plans, opinions, and open topics worth following up later. Merge duplicates, drop outdated items, max 20 notes, each a short English sentence.
                """
                let msgs = [OllamaMessage(role: "system", content: "You maintain a concise memory of a language learner. Output JSON only."),
                            OllamaMessage(role: "user", content: prompt)]
                if let upd = try? await c.decode(MemoryUpdate.self, messages: msgs, schema: Schemas.memory, temperature: 0.1, numPredict: 500),
                   !upd.notes.isEmpty {
                    store.setMemory(upd.notes)
                }
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
