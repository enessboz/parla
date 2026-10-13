import SwiftUI

@MainActor
struct VocabView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case cards = "Kartlar", quiz = "Test"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .cards
    @State private var level = "Tümü"

    private var words: [VocabWord] {
        level == "Tümü" ? AppContent.vocabulary : AppContent.vocabulary.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Picker("Seviye", selection: $level) {
                    ForEach(["Tümü", "A1", "A2", "B1"], id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 160)
            }
            .padding(16)
            Divider()
            Group {
                switch mode {
                case .cards: FlashcardsView(words: words).id(level)
                case .quiz: QuizView(words: words).id(level)
                }
            }
        }
        .navigationTitle("Kelimeler")
    }
}

@MainActor
struct FlashcardsView: View {
    @Environment(DataStore.self) private var store
    @Environment(PracticeViewModel.self) private var vm
    let words: [VocabWord]

    @State private var session: [VocabWord] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var known = 0
    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if !started {
                let due = store.dueCount(words)
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text(due > 0 ? "\(due) kelime tekrar bekliyor" : "Şimdilik tekrar edilecek kelime yok")
                        .font(.title2.bold())
                    Text("Kartlar aralıklı tekrar yöntemiyle gelir: bildiklerin daha seyrek, bilemediklerin sık.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Başla") { start() }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(due == 0)
                }
            } else if index >= session.count {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text("Seans bitti").font(.title.bold())
                    Text("\(session.count) kelimeden \(known) tanesini bildin.").foregroundStyle(.secondary)
                    Button("Tamam") { started = false }.buttonStyle(.borderedProminent)
                }
            } else {
                let w = session[index]
                VStack(spacing: 16) {
                    Text("\(index + 1) / \(session.count)").font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 14) {
                        Text(w.level).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                        Text(w.en).font(.system(size: 44, weight: .bold, design: .rounded))
                        Button { vm.speech.speak(w.en, rate: vm.speechRate) } label: { Image(systemName: "speaker.wave.2.fill") }
                            .buttonStyle(.borderless)
                        if revealed {
                            Divider().frame(maxWidth: 200)
                            Text(w.tr).font(.title.weight(.semibold)).foregroundStyle(.green)
                            Text(w.example).font(.callout).foregroundStyle(.secondary).italic()
                        }
                    }
                    .frame(maxWidth: 440, minHeight: 240)
                    .padding(24)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .onTapGesture { revealed = true }

                    if revealed {
                        HStack(spacing: 14) {
                            Button { answer(false) } label: { Label("Bilemedim", systemImage: "xmark").frame(width: 130) }
                                .tint(.red)
                            Button { answer(true) } label: { Label("Bildim", systemImage: "checkmark").frame(width: 130) }
                                .tint(.green)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        Button("Anlamını göster") { revealed = true }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func start() {
        session = store.dueWords(words, limit: 10)
        index = 0; known = 0; revealed = false; started = true
    }

    private func answer(_ correct: Bool) {
        store.grade(session[index], correct: correct)
        if correct { known += 1 }
        revealed = false
        index += 1
    }
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let word: VocabWord
    let options: [String]
}

@MainActor
struct QuizView: View {
    @Environment(DataStore.self) private var store
    let words: [VocabWord]

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var score = 0
    @State private var picked: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            if questions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(.blue)
                    Text("10 soruluk kelime testi").font(.title2.bold())
                    if let last = store.quizResults.last {
                        Text("Son sonuç: \(last.score)/\(last.total)").foregroundStyle(.secondary)
                    }
                    Button("Testi başlat") { start() }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(words.count < 5)
                }
            } else if finished {
                VStack(spacing: 12) {
                    Image(systemName: score >= 8 ? "star.fill" : "flag.checkered").font(.system(size: 48)).foregroundStyle(.yellow)
                    Text("\(score) / \(questions.count)").font(.system(size: 48, weight: .bold, design: .rounded))
                    Text(score >= 8 ? "Harika!" : score >= 5 ? "İyi gidiyorsun." : "Biraz daha tekrar iyi gelir.")
                        .foregroundStyle(.secondary)
                    Button("Yeni test") { start() }.buttonStyle(.borderedProminent)
                }
            } else {
                let q = questions[index]
                VStack(spacing: 18) {
                    Text("Soru \(index + 1) / \(questions.count)").font(.caption).foregroundStyle(.secondary)
                    Text(q.word.en).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Türkçe anlamı hangisi?").foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        ForEach(q.options, id: \.self) { opt in
                            Button { choose(opt, for: q) } label: {
                                HStack {
                                    Text(opt)
                                    Spacer()
                                    if let p = picked {
                                        if opt == q.word.tr { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                        else if opt == p { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                                    }
                                }
                                .padding(.vertical, 6)
                                .frame(maxWidth: 360)
                            }
                            .buttonStyle(.bordered).controlSize(.large)
                            .disabled(picked != nil)
                        }
                    }
                    if picked != nil {
                        Button(index + 1 == questions.count ? "Bitir" : "Sonraki") { next() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func start() {
        let pool = AppContent.vocabulary
        questions = words.shuffled().prefix(10).map { w in
            let wrong = pool.filter { $0.tr != w.tr }.shuffled().prefix(3).map(\.tr)
            return QuizQuestion(word: w, options: ([w.tr] + wrong).shuffled())
        }
        index = 0; score = 0; picked = nil; finished = false
    }

    private func choose(_ opt: String, for q: QuizQuestion) {
        picked = opt
        let ok = opt == q.word.tr
        if ok { score += 1 }
        store.grade(q.word, correct: ok)
    }

    private func next() {
        picked = nil
        if index + 1 >= questions.count {
            finished = true
            store.record(quiz: QuizResult(date: .now, score: score, total: questions.count))
        } else {
            index += 1
        }
    }
}
