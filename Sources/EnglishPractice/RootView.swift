import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Panel"
    case practice = "Konuşma Pratiği"
    case curriculum = "Dersler"
    case vocab = "Kelimeler"
    case mistakes = "Hatalarım"
    case smart = "Özel Dersler"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "chart.bar.xaxis"
        case .practice: "bubble.left.and.bubble.right.fill"
        case .curriculum: "book.fill"
        case .vocab: "rectangle.stack.fill"
        case .mistakes: "exclamationmark.bubble.fill"
        case .smart: "wand.and.stars"
        }
    }
    var color: Color {
        switch self {
        case .dashboard: .teal
        case .practice: .blue
        case .curriculum: .indigo
        case .vocab: .green
        case .mistakes: .red
        case .smart: .purple
        }
    }
}

@MainActor
struct RootView: View {
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { s in
                Label {
                    Text(s.rawValue)
                } icon: {
                    Image(systemName: s.icon).foregroundStyle(s.color)
                }
                .padding(.vertical, 3)
                .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView(selection: $selection)
            case .practice: PracticeView()
            case .curriculum: CurriculumView()
            case .vocab: VocabView()
            case .mistakes: MistakesView()
            case .smart: LessonsView()
            }
        }
    }
}

@MainActor
struct SettingsView: View {
    @AppStorage("ollamaHost") private var host = "http://localhost:11434"
    @AppStorage("ollamaModel") private var model = "gemma3:4b"
    @State private var installed: [String] = []
    @AppStorage("autoSpeak") private var autoSpeak = true
    @AppStorage("speechRate") private var rate = 0.5

    var body: some View {
        Form {
            TextField("Ollama adresi", text: $host)
            if installed.isEmpty {
                TextField("Model", text: $model)
            } else {
                Picker("Model", selection: $model) {
                    ForEach(installed.contains(model) ? installed : installed + [model], id: \.self) { Text($0).tag($0) }
                }
            }
            Toggle("Cevapları sesli oku", isOn: $autoSpeak)
            HStack { Text("Konuşma hızı"); Slider(value: $rate, in: 0.3...0.7) }
        }
        .padding(20)
        .frame(width: 420)
        .task { installed = (try? await OllamaClient(host: host, model: model).models()) ?? [] }
    }
}
