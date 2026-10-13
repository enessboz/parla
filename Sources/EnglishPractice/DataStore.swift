import Foundation
import Observation

struct QuizResult: Codable, Hashable {
    var date: Date
    var score: Int
    var total: Int
}

/// Everything that is persisted, in one file (~/Library/Application Support/EnglishPractice/data.json).
private struct Snapshot: Codable {
    var mistakes: [Mistake] = []
    var lessons: [SavedLesson] = []
    var activity: [String: Int] = [:]
    var completedLessons: Set<String> = []
    var vocabBox: [String: Int] = [:]
    var vocabDue: [String: Date] = [:]
    var quizResults: [QuizResult] = []
}

extension Snapshot {
    // Tolerant decoding so files written by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mistakes = try c.decodeIfPresent([Mistake].self, forKey: .mistakes) ?? []
        lessons = try c.decodeIfPresent([SavedLesson].self, forKey: .lessons) ?? []
        activity = try c.decodeIfPresent([String: Int].self, forKey: .activity) ?? [:]
        completedLessons = try c.decodeIfPresent(Set<String>.self, forKey: .completedLessons) ?? []
        vocabBox = try c.decodeIfPresent([String: Int].self, forKey: .vocabBox) ?? [:]
        vocabDue = try c.decodeIfPresent([String: Date].self, forKey: .vocabDue) ?? [:]
        quizResults = try c.decodeIfPresent([QuizResult].self, forKey: .quizResults) ?? []
    }
}

@MainActor
@Observable
final class DataStore {
    var mistakes: [Mistake] = []
    var lessons: [SavedLesson] = []
    var activity: [String: Int] = [:]
    var completedLessons: Set<String> = []
    var vocabBox: [String: Int] = [:]
    var vocabDue: [String: Date] = [:]
    var quizResults: [QuizResult] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnglishPractice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            mistakes = s.mistakes; lessons = s.lessons; activity = s.activity
            completedLessons = s.completedLessons; vocabBox = s.vocabBox
            vocabDue = s.vocabDue; quizResults = s.quizResults
        }
    }

    // MARK: Mistakes & lessons

    func add(_ m: Mistake) { mistakes.insert(m, at: 0); save() }
    func add(_ l: SavedLesson) { lessons.insert(l, at: 0); save() }
    func deleteLesson(_ id: UUID) { lessons.removeAll { $0.id == id }; save() }
    func clearMistakes() { mistakes.removeAll(); save() }

    // MARK: Activity & streak

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func recordActivity(_ n: Int = 1) {
        activity[Self.dayKey(.now), default: 0] += n
        save()
    }

    var todayActivity: Int { activity[Self.dayKey(.now)] ?? 0 }

    /// Consecutive active days ending today (or yesterday, if today has no activity yet).
    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if (activity[Self.dayKey(day)] ?? 0) == 0 { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while (activity[Self.dayKey(day)] ?? 0) > 0 {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    /// Activity for the last `days` days, oldest first.
    func recentActivity(days: Int) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { return nil }
            return (d, activity[Self.dayKey(d)] ?? 0)
        }
    }

    // MARK: Curriculum

    func complete(lesson id: String) {
        completedLessons.insert(id)
        recordActivity(3)
    }

    // MARK: Vocabulary (Leitner boxes)

    private static let intervals: [TimeInterval] = [600, 86_400, 3 * 86_400, 7 * 86_400, 21 * 86_400]

    var masteredCount: Int { vocabBox.values.filter { $0 >= 3 }.count }

    func dueWords(_ all: [VocabWord], limit: Int) -> [VocabWord] {
        let now = Date()
        return all
            .filter { (vocabDue[$0.id] ?? .distantPast) <= now }
            .sorted { (vocabDue[$0.id] ?? .distantPast) < (vocabDue[$1.id] ?? .distantPast) }
            .prefix(limit).map { $0 }
    }

    func dueCount(_ all: [VocabWord]) -> Int {
        let now = Date()
        return all.filter { (vocabDue[$0.id] ?? .distantPast) <= now }.count
    }

    func grade(_ word: VocabWord, correct: Bool) {
        let box = correct ? min((vocabBox[word.id] ?? 0) + 1, 4) : 0
        vocabBox[word.id] = box
        vocabDue[word.id] = Date().addingTimeInterval(Self.intervals[box])
        activity[Self.dayKey(.now), default: 0] += 1
        save()
    }

    func record(quiz: QuizResult) {
        quizResults.append(quiz)
        save()
    }

    private func save() {
        let s = Snapshot(mistakes: mistakes, lessons: lessons, activity: activity,
                         completedLessons: completedLessons, vocabBox: vocabBox,
                         vocabDue: vocabDue, quizResults: quizResults)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }
}
