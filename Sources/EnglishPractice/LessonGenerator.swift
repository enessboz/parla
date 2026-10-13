import Foundation

struct MistakeSummary: Identifiable {
    let id: String          // category
    let kind: ErrorCategory
    let count: Int
    let examples: [Mistake]
}

enum LessonGenerator {
    /// Groups recent mistakes by category, most frequent first.
    static func summarize(_ mistakes: [Mistake]) -> [MistakeSummary] {
        Dictionary(grouping: mistakes, by: \.category)
            .map { MistakeSummary(id: $0.key, kind: ErrorCategory(rawValue: $0.key) ?? .other,
                                  count: $0.value.count, examples: Array($0.value.sorted { $0.date > $1.date }.prefix(8))) }
            .sorted { $0.count > $1.count }
    }

    @MainActor
    static func generate(for summary: MistakeSummary, client: OllamaClient) async throws -> SavedLesson {
        let samples = summary.examples
            .map { "- \"\($0.original)\" → \"\($0.fixed)\"" }
            .joined(separator: "\n")
        let isPron = summary.kind == .pronunciation
        let prompt = """
        A Turkish learner of English repeatedly makes this kind of mistake: \(summary.kind.rawValue).
        Their real examples:
        \(samples)

        Write a short targeted lesson. title: short, in English. explanation: 3-5 sentences in Turkish explaining the rule\(isPron ? " and how to pronounce these words (give a simple phonetic hint)" : "") using their own examples. examples: 4 correct English example sentences. exercises: 5 items; \(isPron ? "prompt is a short sentence containing the problem words to read aloud, answer is the same sentence" : "prompt is an English sentence with the blank shown as ___, answer is the missing word(s)").
        """
        let content = try await client.decode(
            LessonContent.self,
            messages: [OllamaMessage(role: "user", content: prompt)],
            schema: Schemas.lesson, temperature: 0.5)
        let data = try JSONEncoder().encode(content)
        let lesson = SavedLesson(title: content.title, json: data, focus: summary.kind.rawValue)
        return lesson
    }
}
