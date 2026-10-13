import Foundation
import Security

/// Common interface for the local (Ollama) and cloud (Claude) backends.
protocol LLMClient {
    func stream(_ messages: [OllamaMessage], numPredict: Int, temperature: Double) -> AsyncThrowingStream<String, Error>
    func decode<T: Decodable>(_ type: T.Type, messages: [OllamaMessage], schema: [String: Any], temperature: Double, numPredict: Int) async throws -> T
    func warmUp() async
}

extension OllamaClient: LLMClient {}

// MARK: - Claude API

struct ClaudeClient: LLMClient {
    var apiKey: String
    var model = "claude-haiku-5-5"

    /// Splits out the system prompt and makes the turns alternate, starting with a user turn.
    private func normalize(_ messages: [OllamaMessage]) -> (system: String, turns: [[String: String]]) {
        let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        var turns: [[String: String]] = []
        for m in messages where m.role != "system" {
            if turns.isEmpty && m.role != "user" { continue }
            if let last = turns.last, last["role"] == m.role {
                turns[turns.count - 1]["content"] = (last["content"] ?? "") + "\n" + m.content
            } else {
                turns.append(["role": m.role, "content": m.content])
            }
        }
        return (system, turns)
    }

    private func makeRequest(system: String, turns: [[String: String]], maxTokens: Int, temperature: Double, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw OllamaError.unreachable }
        var body: [String: Any] = [
            "model": model, "max_tokens": maxTokens, "temperature": temperature,
            "messages": turns, "stream": stream,
        ]
        if !system.isEmpty { body["system"] = system }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func apiError(status: Int, body: String) -> OllamaError {
        if status == 401 { return .api("Claude API anahtarı geçersiz. Ayarlar'dan (⌘,) kontrol et.") }
        if status == 429 { return .api("Claude API istek sınırına takıldı, biraz sonra tekrar dene.") }
        if status == 400, body.contains("credit") { return .api("Claude API hesabında kredi yok (console.anthropic.com › Billing).") }
        return .api("Claude API hatası (\(status)): \(body.prefix(200))")
    }

    func stream(_ messages: [OllamaMessage], numPredict: Int, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let (system, turns) = normalize(messages)
        let req = try? makeRequest(system: system, turns: turns, maxTokens: numPredict, temperature: temperature, stream: true)
        return AsyncThrowingStream { cont in
            guard let req else { cont.finish(throwing: OllamaError.unreachable); return }
            let task = Task {
                do {
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do { (bytes, response) = try await URLSession.shared.bytes(for: req) }
                    catch { throw OllamaError.api("İnternet bağlantısı yok ya da Claude API'ye ulaşılamadı.") }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw Self.apiError(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let d = json.data(using: .utf8),
                              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        if o["type"] as? String == "content_block_delta",
                           let delta = o["delta"] as? [String: Any], let t = delta["text"] as? String { cont.yield(t) }
                        if o["type"] as? String == "message_stop" { break }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    func decode<T: Decodable>(_ type: T.Type, messages: [OllamaMessage], schema: [String: Any], temperature: Double, numPredict: Int) async throws -> T {
        var (system, turns) = normalize(messages)
        let schemaText = (try? JSONSerialization.data(withJSONObject: schema)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        system += "\n\nReturn ONLY a valid JSON object (no markdown, no commentary) that matches this JSON Schema:\n\(schemaText)"
        let req = try makeRequest(system: system, turns: turns, maxTokens: max(numPredict, 600), temperature: temperature, stream: false)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw OllamaError.api("İnternet bağlantısı yok ya da Claude API'ye ulaşılamadı.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.apiError(status: status, body: String(data: data, encoding: .utf8) ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              var text = content.first?["text"] as? String else { throw OllamaError.badResponse("boş yanıt") }
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b { text = String(text[a...b]) }
        do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
        catch { throw OllamaError.badResponse(text) }
    }

    func warmUp() async {}
}

// MARK: - Keychain (API key)

enum Keychain {
    private static let service = "com.enessboz.englishpractice"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - OpenAI API (ChatGPT models)

struct OpenAIClient: LLMClient {
    var apiKey: String
    var model: String

    /// Reasoning-style models reject a custom temperature.
    private var supportsTemperature: Bool {
        !(model.hasPrefix("gpt-5") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4"))
    }

    private var isReasoning: Bool { !supportsTemperature }

    private func makeRequest(_ messages: [OllamaMessage], maxTokens: Int, temperature: Double, stream: Bool, json: Bool) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw OllamaError.unreachable }
        // Reasoning models spend part of the budget on hidden thinking, so give them more room.
        var body: [String: Any] = [
            "model": model, "stream": stream,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_completion_tokens": isReasoning ? max(maxTokens * 8, 1500) : maxTokens,
        ]
        if model == "gpt-5" || model == "gpt-5-mini" || model == "gpt-5-nano" { body["reasoning_effort"] = "minimal" }
        if supportsTemperature { body["temperature"] = temperature }
        if json { body["response_format"] = ["type": "json_object"] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func apiError(status: Int, body: String) -> OllamaError {
        if status == 401 { return .api("OpenAI API anahtarı geçersiz. Ayarlar'dan (⌘,) kontrol et.") }
        if body.contains("insufficient_quota") { return .api("OpenAI hesabında kredi/kota yok (platform.openai.com › Billing).") }
        if status == 429 { return .api("OpenAI istek sınırına takıldı, biraz sonra tekrar dene.") }
        if status == 404 || body.contains("model_not_found") { return .api("OpenAI bu modeli bulamadı ya da erişimin yok. Ayarlar'dan başka bir model yaz (ör. gpt-4o-mini).") }
        return .api("OpenAI API hatası (\(status)): \(body.prefix(200))")
    }

    func stream(_ messages: [OllamaMessage], numPredict: Int, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let req = try? makeRequest(messages, maxTokens: numPredict, temperature: temperature, stream: true, json: false)
        return AsyncThrowingStream { cont in
            guard let req else { cont.finish(throwing: OllamaError.unreachable); return }
            let task = Task {
                do {
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do { (bytes, response) = try await URLSession.shared.bytes(for: req) }
                    catch { throw OllamaError.api("İnternet bağlantısı yok ya da OpenAI API'ye ulaşılamadı.") }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw Self.apiError(status: status, body: body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = o["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let t = delta["content"] as? String, !t.isEmpty else { continue }
                        cont.yield(t)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    func decode<T: Decodable>(_ type: T.Type, messages: [OllamaMessage], schema: [String: Any], temperature: Double, numPredict: Int) async throws -> T {
        let schemaText = (try? JSONSerialization.data(withJSONObject: schema)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var msgs = messages
        let instruction = "\n\nReturn ONLY a valid JSON object (no markdown) that matches this JSON Schema:\n\(schemaText)"
        if let i = msgs.firstIndex(where: { $0.role == "system" }) { msgs[i].content += instruction }
        else { msgs.insert(OllamaMessage(role: "system", content: "Output JSON only." + instruction), at: 0) }

        let req = try makeRequest(msgs, maxTokens: max(numPredict, 800), temperature: temperature, stream: false, json: true)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw OllamaError.api("İnternet bağlantısı yok ya da OpenAI API'ye ulaşılamadı.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.apiError(status: status, body: String(data: data, encoding: .utf8) ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              var text = message["content"] as? String else { throw OllamaError.badResponse("boş yanıt") }
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b { text = String(text[a...b]) }
        do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
        catch { throw OllamaError.badResponse(text) }
    }

    func warmUp() async {}
}

/// API keys: Keychain when it works; if the Keychain refuses (common for unsigned apps), a private fallback in UserDefaults.
enum Secrets {
    private static func fallbackKey(_ a: String) -> String { "secret.\(a)" }

    static func get(_ account: String) -> String? {
        if let v = Keychain.get(account), !v.isEmpty { return v }
        if let v = UserDefaults.standard.string(forKey: fallbackKey(account)), !v.isEmpty { return v }
        return nil
    }

    static func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if Keychain.set(trimmed, for: account), Keychain.get(account) == trimmed || trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: fallbackKey(account))
        } else {
            UserDefaults.standard.set(trimmed, forKey: fallbackKey(account))
        }
    }
}

// MARK: - Backend selection

struct MissingKeyClient: LLMClient {
    var provider: String
    private var error: OllamaError { .api("\(provider) için API anahtarı yok. Ayarlar'dan (⌘,) anahtarı gir ya da yerel modele (Ollama) dön.") }
    func stream(_ messages: [OllamaMessage], numPredict: Int, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let e = error
        return AsyncThrowingStream { $0.finish(throwing: e) }
    }
    func decode<T: Decodable>(_ type: T.Type, messages: [OllamaMessage], schema: [String: Any], temperature: Double, numPredict: Int) async throws -> T { throw error }
    func warmUp() async {}
}

enum ClientFactory {
    static let defaultClaude = "claude-haiku-5-5"
    static let defaultOpenAI = "gpt-4o"

    static func current() -> any LLMClient {
        let d = UserDefaults.standard
        switch d.string(forKey: "provider") ?? "ollama" {
        case "claude":
            guard let key = Secrets.get("anthropic") else { return MissingKeyClient(provider: "Claude") }
            let m = d.string(forKey: "claudeModel") ?? ""
            return ClaudeClient(apiKey: key, model: m.isEmpty ? defaultClaude : m)
        case "openai":
            guard let key = Secrets.get("openai") else { return MissingKeyClient(provider: "OpenAI") }
            let m = d.string(forKey: "openaiModel") ?? ""
            return OpenAIClient(apiKey: key, model: m.isEmpty ? defaultOpenAI : m)
        default:
            return OllamaClient(host: d.string(forKey: "ollamaHost") ?? "http://localhost:11434",
                                model: d.string(forKey: "ollamaModel") ?? "gemma3:4b")
        }
    }

    /// Shown in the chat header so it is always clear who you are talking to.
    static func label() -> String {
        let d = UserDefaults.standard
        switch d.string(forKey: "provider") ?? "ollama" {
        case "claude": return "Claude · " + ((d.string(forKey: "claudeModel") ?? "").isEmpty ? defaultClaude : d.string(forKey: "claudeModel")!)
        case "openai": return "OpenAI · " + ((d.string(forKey: "openaiModel") ?? "").isEmpty ? defaultOpenAI : d.string(forKey: "openaiModel")!)
        default: return "Ollama (yerel) · " + (d.string(forKey: "ollamaModel") ?? "gemma3:4b")
        }
    }
}

// MARK: - Live model lists

enum ModelCatalog {
    static let claudeFallback = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"]

    static func openAI(key: String) async -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return [] }
        let banned = ["audio", "realtime", "transcribe", "tts", "image", "search", "instruct", "embedding", "moderation", "vision", "codex", "whisper", "dall", "computer", "chat-latest", "deep-research"]
        let ids = list.compactMap { $0["id"] as? String }.filter { id in
            (id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4"))
            && !banned.contains(where: { id.contains($0) })
            && id.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil
            && id.range(of: #"-\d{4}$"#, options: .regularExpression) == nil
        }
        return Array(Set(ids)).sorted()
    }

    /// The strongest few models first (newest GPT-5 family, then 4.1), always followed by gpt-4o.
    static func recommendedOpenAI(_ all: [String]) -> [String] {
        func rank(_ id: String) -> (Int, String) {
            if id.hasPrefix("gpt-5") { return (0, id) }
            if id.hasPrefix("gpt-4.1") { return (1, id) }
            if id.hasPrefix("o3") || id.hasPrefix("o4") { return (2, id) }
            return (9, id)
        }
        var top = all.filter { rank($0).0 < 9 && !$0.contains("nano") }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra.0 != rb.0 { return ra.0 < rb.0 }
                let am = a.contains("mini"), bm = b.contains("mini")
                if am != bm { return !am }
                return a > b
            }
        top = Array(top.prefix(4))
        for must in ["gpt-4o", "gpt-4o-mini"] where all.contains(must) && !top.contains(must) { top.append(must) }
        if top.isEmpty { top = ["gpt-4o", "gpt-4o-mini"] }
        return top
    }

    static func claude(key: String) async -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=100") else { return claudeFallback }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return claudeFallback }
        let ids = list.compactMap { $0["id"] as? String }
        return ids.isEmpty ? claudeFallback : ids
    }
}
