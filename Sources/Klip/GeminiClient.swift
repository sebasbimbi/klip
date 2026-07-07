import Foundation

/// Cliente de Google Gemini para transcripción de audio (proveedor alternativo a OpenAI).
/// La clave se lee del archivo local (gemini.key); se envía vía el header x-goog-api-key (no en la URL).
final class GeminiClient {
    static let shared = GeminiClient()
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    var hasAPIKey: Bool {
        guard let v = SecretStore.get(.gemini) else { return false }
        return !v.isEmpty
    }

    private func apiKey() throws -> String {
        guard let v = SecretStore.get(.gemini), !v.isEmpty else { throw OpenAIError.missingAPIKey }
        return v
    }

    /// `model` lo resuelve el llamador (Recorder) en el MainActor y lo pasa aquí, para no leer
    /// `Settings.shared` desde el hilo de transcripción (evita el data race con un @Published).
    func transcribe(audioURL: URL, language: String?, model: String, vocabulary: String = "") async throws -> String {
        let key = try apiKey()
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gemini-flash-latest" : model.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try Data(contentsOf: audioURL)
        let base64 = data.base64EncodedString()
        // Sin pista de idioma cuando es "auto-detect": deja que el modelo transcriba en el idioma propio del audio.
        let langHint = (language?.isEmpty == false) ? " Primary language: \(language!)." : ""
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        let vocabHint = vocab.isEmpty ? ""
            : " These names/terms may appear; spell them exactly as written: \(vocab)."
        let prompt = "Transcribe this audio verbatim. Return ONLY the transcription, "
            + "with no comments, headings or formatting.\(langHint)\(vocabHint)"

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(resolvedModel):generateContent")!

        // `thinkingBudget:0` desactiva el paso de razonamiento (el alias "-latest" ahora resuelve a un modelo
        // thinking que quema tokens de "thought" y puede devolver una respuesta vacía para una transcripción simple).
        // Pero algunos modelos seleccionables por el usuario rechazan thinkingConfig con un 400 — en ese caso se reintenta una vez sin él.
        func send(includeThinking: Bool) async throws -> Data {
            var gen: [String: Any] = ["temperature": 0]
            if includeThinking { gen["thinkingConfig"] = ["thinkingBudget": 0] }
            let payload: [String: Any] = [
                "contents": [["role": "user", "parts": [
                    ["inline_data": ["mime_type": Self.mimeType(for: audioURL), "data": base64]],
                    ["text": prompt]
                ]]],
                "generationConfig": gen
            ]
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            req.timeoutInterval = 120

            let respData: Data, resp: URLResponse
            do { (respData, resp) = try await session.data(for: req) } catch { throw OpenAIError.transport(error) }
            guard let http = resp as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                struct E: Decodable { struct Err: Decodable { let message: String }; let error: Err }
                let msg = (try? JSONDecoder().decode(E.self, from: respData))?.error.message
                    ?? (String(data: respData, encoding: .utf8) ?? "")
                if http.statusCode == 400, includeThinking, msg.lowercased().contains("thinking") {
                    return try await send(includeThinking: false)   // este modelo no acepta thinkingConfig
                }
                throw OpenAIError.http(status: http.statusCode, message: "Gemini: \(msg)")
            }
            return respData
        }
        let respData = try await send(includeThinking: true)

        struct R: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String?; let thought: Bool? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        guard let r = try? JSONDecoder().decode(R.self, from: respData) else { throw OpenAIError.invalidResponse }
        let text = (r.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }      // omite las partes de razonamiento; conserva solo la respuesta
            .compactMap { $0.text }
            .joined()
        // Un 200 sin texto usable significa que el modelo no devolvió nada (bloqueo de seguridad, corte por presupuesto
        // de tokens, candidato vacío) — se expone como error para que quede logueado y sea distinguible del silencio real.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIError.invalidResponse
        }
        return text
    }

    /// Tipos MIME de audio que Gemini acepta. .m4a/.mp4/.m4b son contenedores MP4 (audio/mp4); reservar
    /// audio/aac para streams .aac ADTS genuinos.
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3", "mpeg", "mpga":        return "audio/mp3"
        case "wav":                        return "audio/wav"
        case "aiff", "aif":                return "audio/aiff"
        case "ogg", "oga", "opus":         return "audio/ogg"
        case "flac":                       return "audio/flac"
        case "aac":                        return "audio/aac"
        case "m4a", "mp4", "m4b":          return "audio/mp4"
        default:                           return "audio/mp4"
        }
    }
}

/// Selecciona el proveedor de IA configurado para la transcripción.
enum AIProvider {
    static var selected: String { Settings.shared.aiProvider }

    /// ¿Está listo el proveedor seleccionado? Local (en el dispositivo) no necesita clave; cada proveedor cloud
    /// necesita SU PROPIA clave (sin fallback entre proveedores — elegir Gemini teniendo solo clave de OpenAI no
    /// debe enviar tu audio a OpenAI en silencio; la UI muestra exactamente la sección de clave del proveedor seleccionado).
    static var hasKey: Bool {
        switch selected {
        case "local":  return true
        case "gemini": return GeminiClient.shared.hasAPIKey
        default:       return OpenAIClient.shared.hasAPIKey
        }
    }

    /// Enruta según el proveedor EFECTIVO resuelto por el llamador en el MainActor (aquí no se relee Settings,
    /// así no hay data race fuera de main ni TOCTOU de proveedor/modelo). `model` ya corresponde a `provider`.
    static func transcribe(provider: String, audioURL: URL, language: String?, model: String, vocabulary: String = "") async throws -> String {
        switch provider {
        case "local":
            // En el dispositivo (WhisperKit): ningún audio sale del Mac. `model` es el nombre del modelo local.
            return try await LocalTranscriber.shared.transcribe(audioURL: audioURL, model: model, language: language, vocabulary: vocabulary)
        case "gemini":
            return try await GeminiClient.shared.transcribe(audioURL: audioURL, language: language, model: model, vocabulary: vocabulary)
        default:
            return try await OpenAIClient.shared.transcribe(audioURL: audioURL, language: language, model: model, vocabulary: vocabulary)
        }
    }
}
