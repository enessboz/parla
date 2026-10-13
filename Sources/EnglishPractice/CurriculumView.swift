import SwiftUI

@MainActor
struct CurriculumView: View {
    @Environment(DataStore.self) private var store
    @State private var selected: String?

    var body: some View {
        HSplitView {
            List(selection: $selected) {
                ForEach(Content.levels) { level in
                    SwiftUI.Section("\(level.code) · \(level.name)") {
                        ForEach(level.lessons) { l in
                            HStack {
                                Image(systemName: store.completedLessons.contains(l.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.completedLessons.contains(l.id) ? .green : .secondary)
                                Text(l.content.title)
                            }
                            .tag(l.id)
                        }
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 290, maxWidth: 340)

            if let lesson = Content.allLessons.first(where: { $0.id == selected }) {
                LessonDetail(content: lesson.content, onComplete: { store.complete(lesson: lesson.id) })
                    .id(lesson.id)
            } else {
                ContentUnavailableView("Ders seç", systemImage: "book",
                                       description: Text("Soldan bir ders seçerek başla."))
            }
        }
        .navigationTitle("Dersler")
        .onAppear {
            if selected == nil {
                selected = (Content.allLessons.first(where: { !store.completedLessons.contains($0.id) }) ?? Content.allLessons.first)?.id
            }
        }
    }
}
