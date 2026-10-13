import SwiftUI

@MainActor
struct LessonsView: View {
    @Environment(PracticeViewModel.self) private var vm
    @Environment(DataStore.self) private var store
    private var mistakes: [Mistake] { store.mistakes }
    private var lessons: [SavedLesson] { store.lessons }
    @State private var generating: String?
    @State private var error: String?
    @State private var selected: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selected) {
                    SwiftUI.Section("Senin için önerilen") {
                        ForEach(LessonGenerator.summarize(mistakes).prefix(5)) { g in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(g.kind.turkish)
                                    Text("\(g.count) hata").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if generating == g.id { ProgressView().controlSize(.small) }
                                else { Button("Ders oluştur") { generate(g) }.disabled(generating != nil) }
                            }
                        }
                    }
                    SwiftUI.Section("Derslerim") {
                        ForEach(lessons) { l in Text(l.title).tag(l.id) }
                            .onDelete { $0.map { lessons[$0].id }.forEach(store.deleteLesson) }
                    }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.red).padding(8) }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            if let sel = lessons.first(where: { $0.id == selected }), let content = sel.content {
                LessonDetail(content: content).id(sel.id)
            } else {
                ContentUnavailableView("Ders seç", systemImage: "graduationcap",
                                       description: Text("Sık yaptığın hatalardan kişisel ders oluştur."))
            }
        }
        .navigationTitle("Özel Dersler")
    }

    private func generate(_ g: MistakeSummary) {
        generating = g.id; error = nil
        let client = vm.client
        Task {
            do { let l = try await LessonGenerator.generate(for: g, client: client); store.add(l); selected = l.id }
            catch { self.error = error.localizedDescription }
            generating = nil
        }
    }
}

@MainActor
struct LessonDetail: View {
    @Environment(PracticeViewModel.self) private var vm
    let content: LessonContent
    @State private var answers: [Int: String] = [:]
    @State private var checked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(content.title).font(.title.bold())
                Text(content.explanation)
                GroupBox("Örnekler") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(content.examples, id: \.self) { ex in
                            HStack {
                                Button { vm.speech.speak(ex, rate: vm.speechRate) } label: { Image(systemName: "speaker.wave.2") }
                                    .buttonStyle(.borderless)
                                Text(ex)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Alıştırmalar") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(content.exercises.enumerated()), id: \.offset) { i, ex in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ex.prompt)
                                HStack {
                                    TextField("Cevap", text: Binding(get: { answers[i] ?? "" }, set: { answers[i] = $0 }))
                                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                                    if checked {
                                        let ok = normalize(answers[i] ?? "") == normalize(ex.answer)
                                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(ok ? .green : .red)
                                        if !ok { Text(ex.answer).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        Button(checked ? "Sıfırla" : "Kontrol et") {
                            if checked { answers = [:]; checked = false } else { checked = true }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }
}
