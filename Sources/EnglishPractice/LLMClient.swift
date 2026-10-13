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

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
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

    private func makeRequest(_ messages: [OllamaMessage], maxTokens: Int, temperature: Double, stream: Bool, json: Bool) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw OllamaError.unreachable }
        var body: [String: Any] = [
            "model": model, "stream": stream,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_completion_tokens": maxTokens,
        ]
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
