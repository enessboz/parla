import SwiftUI

@MainActor
struct MistakesView: View {
    @Environment(DataStore.self) private var store
    private var mistakes: [Mistake] { store.mistakes }

    var body: some View {
        let groups = LessonGenerator.summarize(mistakes)
        Group {
            if mistakes.isEmpty {
                ContentUnavailableView("Henüz hata yok", systemImage: "checkmark.seal",
                                       description: Text("Konuşma pratiği yaptıkça hatalar burada toplanır."))
            } else {
                List {
                    ForEach(groups) { g in
                        DisclosureGroup {
                            ForEach(g.examples) { m in
                                VStack(alignment: .leading) {
                                    HStack { Text(m.original).strikethrough().foregroundStyle(.red)
                                        Image(systemName: "arrow.right").font(.caption)
                                        Text(m.fixed).foregroundStyle(.green) }
                                    Text(m.explanation).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            HStack { Text(g.kind.turkish).font(.headline); Spacer(); Text("\(g.count)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Hatalarım")
        .toolbar {
            Button("Tümünü sil", role: .destructive) {
                store.clearMistakes()
            }.disabled(mistakes.isEmpty)
        }
    }
}
