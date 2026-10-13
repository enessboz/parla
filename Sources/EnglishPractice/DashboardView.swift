import SwiftUI
import Charts

@MainActor
struct DashboardView: View {
    @Environment(DataStore.self) private var store
    @Binding var selection: AppSection?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        default: return "İyi akşamlar"
        }
    }

    var body: some View {
        let summaries = LessonGenerator.summarize(store.mistakes).prefix(5)
        let due = store.dueCount(AppContent.vocabulary)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(greeting)!").font(.largeTitle.bold())
                    Text(store.todayActivity == 0 ? "Bugün henüz pratik yapmadın." : "Bugün \(store.todayActivity) etkinlik tamamladın.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    StatCard(icon: "flame.fill", color: .orange, value: "\(store.streak)", label: "günlük seri")
                    StatCard(icon: "textformat.abc", color: .blue, value: "\(store.masteredCount)/\(AppContent.vocabulary.count)", label: "öğrenilen kelime")
                    StatCard(icon: "graduationcap.fill", color: .purple, value: "\(store.completedLessons.count)/\(AppContent.allLessons.count)", label: "tamamlanan ders")
                    StatCard(icon: "exclamationmark.bubble.fill", color: .red, value: "\(store.mistakes.count)", label: "kayıtlı hata")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Son 14 gün").font(.headline)
                    Chart(store.recentActivity(days: 14), id: \.date) { item in
                        BarMark(x: .value("Gün", item.date, unit: .day), y: .value("Etkinlik", item.count))
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                    }
                    .frame(height: 160)
                }
                .card()

                if !summaries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("En sık hatalar").font(.headline)
                        Chart(Array(summaries)) { s in
                            BarMark(x: .value("Adet", s.count), y: .value("Kategori", s.kind.turkish))
                                .foregroundStyle(.orange.gradient)
                                .cornerRadius(4)
                        }
                        .frame(height: CGFloat(summaries.count) * 34 + 20)
                    }
                    .card()
                }

                Text("Bugün için öneriler").font(.headline)
                VStack(spacing: 12) {
                    suggestion(icon: "bubble.left.and.bubble.right.fill", color: .blue,
                               title: "Konuşma pratiği", detail: "İngilizce sohbet et, hataların otomatik düzeltilsin.", target: .practice)
                    if due > 0 {
                        suggestion(icon: "rectangle.stack.fill", color: .green,
                                   title: "\(due) kelime tekrar bekliyor", detail: "Kısa bir kart seansı hafızayı tazeler.", target: .vocab)
                    }
                    if let top = summaries.first {
                        suggestion(icon: "wand.and.stars", color: .purple,
                                   title: "\(top.kind.turkish) için özel ders", detail: "En çok yaptığın hata türü; sana özel ders üret.", target: .smart)
                    }
                    if let next = AppContent.allLessons.first(where: { !store.completedLessons.contains($0.id) }) {
                        suggestion(icon: "book.fill", color: .indigo,
                                   title: "Sıradaki ders: \(next.content.title)", detail: "Müfredatta kaldığın yerden devam et.", target: .curriculum)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Panel")
    }

    private func suggestion(icon: String, color: Color, title: String, detail: String, target: AppSection) -> some View {
        Button { selection = target } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}
