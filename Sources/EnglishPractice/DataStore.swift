import Foundation
import Observation

/// Simple JSON-file persistence (~/Library/Application Support/EnglishPractice/data.json).
@MainActor
@Observable
final class DataStore {
    var mistakes: [Mistake] = []
    var lessons: [SavedLesson] = []

    private struct Snapshot: Codable {
        var mistakes: [Mistake]
        var lessons: [SavedLesson]
    }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnglishPractice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            mistakes = snap.mistakes
            lessons = snap.lessons
        }
    }

    func add(_ m: Mistake) { mistakes.insert(m, at: 0); save() }
    func add(_ l: SavedLesson) { lessons.insert(l, at: 0); save() }
    func deleteLesson(_ id: UUID) { lessons.removeAll { $0.id == id }; save() }
    func clearMistakes() { mistakes.removeAll(); save() }

    private func save() {
        let snap = Snapshot(mistakes: mistakes, lessons: lessons)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
    }
}
