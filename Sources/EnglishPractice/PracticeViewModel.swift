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

    let speech = SpeechService()

    var client: OllamaClient {
        let d = UserDefaults.standard
        return OllamaClient(host: d.string(forKey: "ollamaHost") ?? "http://localhost:11434",
                            model: d.string(forKey: "ollamaModel") ?? "gemma3:4b")
    }
    var autoSpeak: Bool { UserDefaults.standard.object(forKey: "autoSpeak") as? Bool ?? true }
    var speechRate: Float { Float(UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 0.5) }

    private let system = """
    You are a friendly English conversation partner for a Turkish-speaking learner.
    For every user message return JSON with:
    - reply: a short natural reply (1-3 sentences, simple English) that continues the conversation, ending with a question.
    - corrected: the user's message rewritten with correct grammar (identical if already correct).
    - errors: each distinct mistake found. category must be one of the allowed values; original and fixed are the minimal wrong/right fragments; explanation is one short sentence in Turkish.
    Do not invent errors. Ignore capitalization and punctuation style unless clearly wrong.
    """

    func toggleMic() async {
        if speech.isListening {
            speech.stop()
        } else {
            await speech.start { [weak self] words in
                guard let self else { return }
                self.pendingWords = words
                self.draft = words.map(\.text).joined(separator: " ")
            }
        }
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

        let userID = ChatItem(role: .user, text: text, words: words)
        items.append(userID)

        // Pronunciation: low-confidence words become Mistake rows.
        for w in words where w.isWeak {
            store.add(Mistake(category: ErrorCategory.pronunciation.rawValue, original: w.text.lowercased(),
                                   fixed: w.text.lowercased(), explanation: "Bu kelimeyi net söyleyemedin."))
        }

        var messages = [OllamaMessage(role: "system", content: system)]
        for item in items.suffix(11) {
            messages.append(OllamaMessage(role: item.role == .user ? "user" : "assistant", content: item.text))
        }

        do {
            let turn = try await client.decode(PracticeTurn.self, messages: messages, schema: Schemas.practiceTurn)
            if let idx = items.firstIndex(where: { $0.id == userID.id }) {
                items[idx].corrected = turn.corrected == text ? nil : turn.corrected
                items[idx].errors = turn.errors
            }
            for e in turn.errors {
                store.add(Mistake(category: e.category, original: e.original, fixed: e.fixed, explanation: e.explanation))
            }
            items.append(ChatItem(role: .assistant, text: turn.reply))
            if autoSpeak { speech.speak(turn.reply, rate: speechRate) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
