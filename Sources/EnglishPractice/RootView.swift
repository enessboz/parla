import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case practice = "Konuşma Pratiği"
    case mistakes = "Hatalarım"
    case lessons = "Özel Dersler"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .practice: "bubble.left.and.bubble.right"
        case .mistakes: "exclamationmark.bubble"
        case .lessons: "graduationcap"
        }
    }
}

@MainActor
struct RootView: View {
    @State private var selection: Section? = .practice

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .practice {
            case .practice: PracticeView()
            case .mistakes: MistakesView()
            case .lessons: LessonsView()
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
