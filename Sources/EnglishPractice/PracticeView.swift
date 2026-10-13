import SwiftUI

@MainActor
struct PracticeView: View {
    @Environment(PracticeViewModel.self) private var vm
    @Environment(DataStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            statusBanner
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(vm.items) { item in
                            MessageRow(item: item).id(item.id)
                        }
                        if vm.isBusy { ProgressView().padding() }
                    }
                    .padding(20)
                }
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom))
                .onChange(of: vm.items.count) {
                    if let last = vm.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if let err = vm.errorMessage {
                Text(err).font(.callout).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 6)
            }
            if vm.speech.isListening {
                Text(vm.speech.liveTranscript.isEmpty ? "Dinliyorum…" : vm.speech.liveTranscript)
                    .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 6)
            }

            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { vm.voiceMode }, set: { vm.setVoiceMode($0, store: store) })) {
                    Image(systemName: "waveform")
                }
                .toggleStyle(.button)
                .help("Sesli mod: konuş, cevabı dinle, tekrar konuş (eller serbest)")

                Button { Task { await vm.toggleMic() } } label: {
                    Image(systemName: vm.speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(vm.speech.isListening ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .help("Konuşmak için tıkla")

                TextField("İngilizce yaz veya konuş…", text: $vm.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { Task { await vm.send(store: store) } }

                Button("Gönder") { Task { await vm.send(store: store) } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isBusy)
            }
            .padding(14)
            .background(.bar)
        }
        .navigationTitle("Konuşma Pratiği")
        .onAppear { focused = true }
        .task { await vm.refreshStatus() }
        .alert("İzin gerekli", isPresented: .constant(vm.speech.authorizationDenied)) {
            Button("Tamam") { vm.speech.authorizationDenied = false }
        } message: {
            Text("Sistem Ayarları › Gizlilik ve Güvenlik bölümünden mikrofon ve konuşma tanıma izni ver.")
        }
    }
}

@MainActor
extension PracticeView {
    @ViewBuilder var statusBanner: some View {
        switch vm.ollamaStatus {
        case .down:
            banner("Ollama çalışmıyor. Terminal'de `ollama serve` yaz (ya da Ollama uygulamasını aç).")
        case .modelMissing(let installed):
            banner(installed.isEmpty
                   ? "Hiç model yok. Terminal'de: ollama pull \(UserDefaults.standard.string(forKey: "ollamaModel") ?? "gemma3:4b")"
                   : "Seçili model kurulu değil. Ayarlar'dan (⌘,) şunlardan birini seç: \(installed.joined(separator: ", "))")
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.callout)
            Spacer()
            Button("Yeniden dene") { Task { await vm.refreshStatus() } }
        }
        .padding(10)
        .background(.orange.opacity(0.18))
    }
}

@MainActor
struct MessageRow: View {
    @Environment(PracticeViewModel.self) private var vm
    let item: ChatItem

    var body: some View {
        HStack {
            if item.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                if item.words.isEmpty {
                    Text(item.text).textSelection(.enabled)
                } else {
                    spokenText
                }

                if let c = item.corrected {
                    Divider()
                    Label(c, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).textSelection(.enabled)
                }
                ForEach(item.errors, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ErrorCategory(rawValue: e.category)?.turkish ?? e.category)
                                .font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.2), in: Capsule())
                            Text(e.original).strikethrough().foregroundStyle(.red)
                            Image(systemName: "arrow.right").font(.caption)
                            Text(e.fixed).foregroundStyle(.green)
                        }
                        Text(e.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if item.role == .assistant {
                    Button { vm.speech.speak(item.text, rate: vm.speechRate) } label: {
                        Image(systemName: "speaker.wave.2")
                    }.buttonStyle(.borderless)
                }
            }
            .padding(12)
            .background(item.role == .user ? Color.accentColor.opacity(0.16) : Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            if item.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var spokenText: some View {
        item.words.reduce(Text("")) { acc, w in
            acc + Text(w.text + " ").foregroundColor(w.isWeak ? .orange : .primary)
                .underline(w.isWeak, color: .orange)
        }
        .textSelection(.enabled)
    }
}
