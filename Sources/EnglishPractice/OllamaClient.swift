import Foundation

struct OllamaMessage: Codable {
    var role: String
    var content: String
}

enum OllamaError: LocalizedError {
    case unreachable
    case badResponse(String)
    var errorDescription: String? {
        switch self {
        case .unreachable:
            "Ollama'ya ulaşılamadı. Terminalde `ollama serve` çalışıyor mu ve model indirildi mi (`ollama pull <model>`)?"
        case .badResponse(let s): "Beklenmeyen yanıt: \(s)"
        }
    }
}

struct OllamaClient {
    var host: String
    var model: String

    /// Sends a chat request. When `schema` is given Ollama constrains the output to that JSON schema.
    func chat(_ messages: [OllamaMessage], schema: [String: Any]? = nil, temperature: Double = 0.4) async throws -> String {
        guard let url = URL(string: host)?.appendingPathComponent("api/chat") else { throw OllamaError.unreachable }
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "options": ["temperature": temperature],
        ]
        if let schema { body["format"] = schema }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw OllamaError.unreachable }

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw OllamaError.badResponse(String(data: data, encoding: .utf8) ?? "") }
        return content
    }

    /// Names of locally installed models.
    func models() async throws -> [String] {
        guard let url = URL(string: host)?.appendingPathComponent("api/tags") else { throw OllamaError.unreachable }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) }
        catch { throw OllamaError.unreachable }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["models"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["name"] as? String }.sorted()
    }

    func decode<T: Decodable>(_ type: T.Type, messages: [OllamaMessage], schema: [String: Any], temperature: Double = 0.3) async throws -> T {
        let text = try await chat(messages, schema: schema, temperature: temperature)
        do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
        catch { throw OllamaError.badResponse(text) }
    }
}

// MARK: - Schemas

enum Schemas {
    static let categories = ErrorCategory.allCases.filter { $0 != .pronunciation }.map(\.rawValue)

    static let practiceTurn: [String: Any] = [
        "type": "object",
        "properties": [
            "reply": ["type": "string"],
            "corrected": ["type": "string"],
            "errors": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "category": ["type": "string", "enum": categories],
                        "original": ["type": "string"],
                        "fixed": ["type": "string"],
                        "explanation": ["type": "string"],
                    ],
                    "required": ["category", "original", "fixed", "explanation"],
                ],
            ],
        ],
        "required": ["reply", "corrected", "errors"],
    ]

    static let lesson: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "explanation": ["type": "string"],
            "examples": ["type": "array", "items": ["type": "string"]],
            "exercises": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["prompt": ["type": "string"], "answer": ["type": "string"]],
                    "required": ["prompt", "answer"],
                ],
            ],
        ],
        "required": ["title", "explanation", "examples", "exercises"],
    ]
}
