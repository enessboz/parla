import Foundation

enum ErrorCategory: String, CaseIterable, Codable {
    case tense = "Tense"
    case subjectVerb = "SubjectVerb"
    case article = "Article"
    case preposition = "Preposition"
    case wordOrder = "WordOrder"
    case plural = "Plural"
    case vocabulary = "Vocabulary"
    case spelling = "Spelling"
    case pronunciation = "Pronunciation"
    case other = "Other"

    var turkish: String {
        switch self {
        case .tense: "Zaman"
        case .subjectVerb: "Özne-Yüklem Uyumu"
        case .article: "Article (a/an/the)"
        case .preposition: "Edat"
        case .wordOrder: "Kelime Sırası"
        case .plural: "Çoğul"
        case .vocabulary: "Kelime Seçimi"
        case .spelling: "Yazım"
        case .pronunciation: "Telaffuz"
        case .other: "Diğer"
        }
    }
}

struct Mistake: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: String
    var original: String
    var fixed: String
    var explanation: String
    var date: Date

    init(category: String, original: String, fixed: String, explanation: String, date: Date = .now) {
        self.category = category
        self.original = original
        self.fixed = fixed
        self.explanation = explanation
        self.date = date
    }

    var kind: ErrorCategory { ErrorCategory(rawValue: category) ?? .other }
}

/// Persisted smart lesson; the content is stored as JSON of `LessonContent`.
struct SavedLesson: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var json: Data
    var focus: String
    var date: Date

    init(title: String, json: Data, focus: String, date: Date = .now) {
        self.title = title
        self.json = json
        self.focus = focus
        self.date = date
    }

    var content: LessonContent? { try? JSONDecoder().decode(LessonContent.self, from: json) }
}

struct LessonContent: Codable {
    struct Exercise: Codable, Hashable {
        var prompt: String
        var answer: String
    }
    var title: String
    var explanation: String      // Turkish
    var examples: [String]
    var exercises: [Exercise]
}

// MARK: - Chat (in-memory)

struct DetectedError: Codable, Hashable {
    var category: String
    var original: String
    var fixed: String
    var explanation: String
}

struct PracticeTurn: Codable {
    var reply: String
    var corrected: String
    var errors: [DetectedError]
}

struct Correction: Codable {
    var corrected: String
    var errors: [DetectedError]
}

struct ChatItem: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var corrected: String? = nil
    var errors: [DetectedError] = []
    var words: [SpokenWord] = []     // present when the message was spoken
}

struct SpokenWord: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let confidence: Float            // 0...1, 0 = unknown
    var isWeak: Bool { confidence > 0 && confidence < 0.55 }
}
