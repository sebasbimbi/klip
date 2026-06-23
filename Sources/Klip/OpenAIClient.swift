import Foundation

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(status: Int, message: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L10n.t("ai.err.missingKey")
        case .invalidResponse:
            return L10n.t("ai.err.invalidResponse")
        case .http(let status, let message):
            return "OpenAI \(status): \(message)"
        case .transport(let e):
            return String(format: L10n.t("ai.err.network"), e.localizedDescription)
        }
    }
}

/// OpenAI HTTP client. Reads the key from the Keychain on every request (never hardcodes it).
final class OpenAIClient {
    static let shared = OpenAIClient()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    var hasAPIKey: Bool {
        guard let v = SecretStore.get() else { return false }
        return !v.isEmpty
    }

    private func apiKey() throws -> String {
        guard let v = SecretStore.get(), !v.isEmpty else { throw OpenAIError.missingAPIKey }
        return v
    }

    // MARK: - Audio transcription

    func transcribe(audioURL: URL, language: String?, model: String, vocabulary: String = "") async throws -> String {
        let key = try apiKey()
        let fileData = try Data(contentsOf: audioURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(Self.uploadFilename(for: audioURL))\"\r\n")
        append("Content-Type: \(Self.contentType(for: audioURL))\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        field("model", model)
        if let language, !language.isEmpty { field("language", language) }
        // Bias recognition toward the user's context words/names (Whisper & gpt-4o-transcribe `prompt`).
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty { field("prompt", vocab) }
        field("response_format", "json")
        append("--\(boundary)--\r\n")

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 120

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw OpenAIError.transport(error) }
        try Self.checkHTTP(resp, data)
        struct R: Decodable { let text: String }
        guard let r = try? JSONDecoder().decode(R.self, from: data) else { throw OpenAIError.invalidResponse }
        return r.text
    }

    // MARK: - Reformat to Markdown with AI

    func markdownify(text: String) async throws -> String {
        let key = try apiKey()
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Convert the user's text into clean, well-structured Markdown (headings, lists, emphasis and code blocks where appropriate). Return ONLY the Markdown, with no explanations or wrapping code fences."],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        req.timeoutInterval = 60

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw OpenAIError.transport(error) }
        try Self.checkHTTP(resp, data)
        struct R: Decodable {
            struct Choice: Decodable { struct M: Decodable { let content: String }; let message: M }
            let choices: [Choice]
        }
        guard let r = try? JSONDecoder().decode(R.self, from: data),
              let content = r.choices.first?.message.content else { throw OpenAIError.invalidResponse }
        return content
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3", "mpeg", "mpga": return "audio/mpeg"
        case "mp4", "m4a", "m4b":   return "audio/mp4"
        case "wav":                 return "audio/wav"
        case "webm":                return "audio/webm"
        case "ogg", "oga", "opus":  return "audio/ogg"
        case "flac":                return "audio/flac"
        default:                    return "application/octet-stream"
        }
    }

    /// OpenAI validates the format by the filename extension. Rename extensions the API doesn't accept to
    /// an equivalent it does: .opus (Ogg-Opus) → .ogg; .m4b (MP4 audiobook) → .m4a (same MP4 container).
    private static func uploadFilename(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let rename: [String: String] = ["opus": "ogg", "m4b": "m4a"]
        guard let newExt = rename[ext] else { return url.lastPathComponent }
        let base = url.deletingPathExtension().lastPathComponent
        return (base.isEmpty ? "audio" : base) + "." + newExt
    }

    private static func checkHTTP(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct E: Decodable { struct Err: Decodable { let message: String }; let error: Err }
            let msg = (try? JSONDecoder().decode(E.self, from: data))?.error.message
                ?? (String(data: data, encoding: .utf8) ?? "")
            throw OpenAIError.http(status: http.statusCode, message: msg)
        }
    }
}
