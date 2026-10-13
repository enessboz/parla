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
    @AppStorage("provider") private var provider = "ollama"
    @AppStorage("level") private var level = "A2"
    @AppStorage("ollamaHost") private var host = "http://localhost:11434"
    @AppStorage("ollamaModel") private var model = "gemma3:4b"
    @AppStorage("claudeModel") private var claudeModel = "claude-haiku-5-5"
    @AppStorage("openaiModel") private var openaiModel = "gpt-4o"
    @AppStorage("autoSpeak") private var autoSpeak = true
    @AppStorage("speechRate") private var rate = 0.5
    @AppStorage("silenceSeconds") private var silence = 2.0
    @State private var installed: [String] = []
    @State private var claudeKey = ""
    @State private var openaiKey = ""
    @State private var openaiModels: [String] = []
    @State private var claudeModels: [String] = ModelCatalog.claudeFallback
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Picker("Yapay zekâ", selection: $provider) {
                Text("Claude (bulut)").tag("claude")
                Text("ChatGPT / OpenAI (bulut)").tag("openai")
                Text("Ollama (yerel, ücretsiz)").tag("ollama")
            }
            .onChange(of: provider) { testResult = nil }

            switch provider {
            case "claude":
                SecureField("Claude API anahtarı", text: $claudeKey)
                    .onChange(of: claudeKey) { Secrets.set(claudeKey, for: "anthropic") }
                Picker("Model", selection: $claudeModel) {
                    ForEach(claudeModels.contains(claudeModel) ? claudeModels : claudeModels + [claudeModel], id: \.self) { Text($0).tag($0) }
                }
                Text("haiku: en hızlı · sonnet: dengeli · opus/fable: en güçlü ama daha yavaş ve pahalı. Anahtar: console.anthropic.com (Claude aboneliğinden ayrı, kullandıkça ödenir).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Modelleri yenile") { Task { claudeModels = await ModelCatalog.claude(key: claudeKey) } }
                    .disabled(claudeKey.isEmpty)
            case "openai":
                SecureField("OpenAI API anahtarı", text: $openaiKey)
                    .onChange(of: openaiKey) { Secrets.set(openaiKey, for: "openai") }
                let recommended = ModelCatalog.recommendedOpenAI(openaiModels)
                let rest = openaiModels.filter { !recommended.contains($0) }
                Picker("Model", selection: $openaiModel) {
                    if !openaiModels.isEmpty && !openaiModels.contains(openaiModel) { Text(openaiModel).tag(openaiModel) }
                    if openaiModels.isEmpty {
                        Text("gpt-4o").tag("gpt-4o")
                        Text("gpt-4o-mini").tag("gpt-4o-mini")
                    } else {
                        SwiftUI.Section("Önerilen (en güçlüler)") { ForEach(recommended, id: \.self) { Text($0).tag($0) } }
                        SwiftUI.Section("Tüm modeller") { ForEach(rest, id: \.self) { Text($0).tag($0) } }
                    }
                }
                Text("Anahtarı yapıştırınca model listesi hesabından otomatik gelir. Anahtar: platform.openai.com › API keys. ChatGPT Plus'tan ayrıdır; hesapta kredi olmalı. Çok güçlü (gpt-5 vb.) modeller daha yavaş cevap verir.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Modelleri yenile") { Task { openaiModels = await ModelCatalog.openAI(key: openaiKey) } }
                    .disabled(openaiKey.isEmpty)
            default:
                TextField("Ollama adresi", text: $host)
                if installed.isEmpty {
                    TextField("Model", text: $model)
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(installed.contains(model) ? installed : installed + [model], id: \.self) { Text($0).tag($0) }
                    }
                }
            }

            HStack {
                Button(testing ? "Test ediliyor…" : "Bağlantıyı test et") { runTest() }.disabled(testing)
                if let testResult { Text(testResult).font(.callout).textSelection(.enabled) }
            }
            Text("Şu an aktif: \(ClientFactory.label())").font(.caption).foregroundStyle(.secondary)

            Divider()
            Picker("Seviyem", selection: $level) {
                ForEach(["A1", "A2", "B1", "B2", "C1"], id: \.self) { Text($0).tag($0) }
            }
            Toggle("Cevapları sesli oku", isOn: $autoSpeak)
            HStack { Text("Konuşma hızı"); Slider(value: $rate, in: 0.3...0.7) }
            VStack(alignment: .leading) {
                HStack { Text("Susunca gönder"); Slider(value: $silence, in: 1.0...4.0, step: 0.25); Text(String(format: "%.1f sn", silence)).monospacedDigit() }
                Text("Sesli modda cümlen bitmeden gönderiyorsa artır.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            claudeKey = Secrets.get("anthropic") ?? ""
            openaiKey = Secrets.get("openai") ?? ""
            installed = (try? await OllamaClient(host: host, model: model).models()) ?? []
            if !openaiKey.isEmpty { openaiModels = await ModelCatalog.openAI(key: openaiKey) }
            if !claudeKey.isEmpty { claudeModels = await ModelCatalog.claude(key: claudeKey) }
        }
        .onChange(of: openaiKey) {
            guard openaiKey.count > 20 else { return }
            Task { openaiModels = await ModelCatalog.openAI(key: openaiKey) }
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let client = ClientFactory.current()
        Task {
            var out = ""
            do {
                for try await chunk in client.stream([OllamaMessage(role: "user", content: "Say hello in exactly three words.")], numPredict: 30, temperature: 0.2) {
                    out += chunk
                }
                testResult = out.isEmpty ? "⚠️ Bağlandı ama boş cevap geldi (model çok kısa bütçeyle düşünüyor olabilir, başka model dene)." : "✅ \(ClientFactory.label()): \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                testResult = "❌ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
