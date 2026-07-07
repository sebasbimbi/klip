import Foundation
import WhisperKit

/// Transcripción en el dispositivo con WhisperKit (Whisper sobre Core ML). Ningún audio sale del Mac y no
/// se necesita API key. El modelo Core ML se descarga una vez en el primer uso y se cachea; el pipeline se
/// mantiene en memoria y se reutiliza mientras el modelo elegido no cambie.
actor LocalTranscriber {
    static let shared = LocalTranscriber()

    private var pipe: WhisperKit?
    private var loadedModel: String?
    /// Pasa a true cuando un pipeline termina de cargar en esta sesión. La primera carga en el dispositivo paga
    /// una especialización única de Core ML / Neural Engine (~20 s, después cacheada en disco); la UI lo lee
    /// (best-effort, de ahí nonisolated) para mostrar "Preparando modelo…" en vez de un spinner pelado hasta estar listo.
    nonisolated(unsafe) static private(set) var pipelineReady = false
    /// Serializa las decodificaciones en el dispositivo: la instancia compartida de WhisperKit tiene estado
    /// mutable (progreso, tiempos, decoder de Core ML) que NO es seguro ejecutar en concurrencia. Soltar varios
    /// archivos de audio a la vez provocaría carreras. Cada llamada se encadena tras la decodificación anterior.
    private var serialTail: Task<Void, Never> = Task {}

    /// Nombre amigable del modelo → identificador de modelo de WhisperKit (WhisperKit los resuelve contra su repo de HF).
    static let models: [(id: String, label: String, note: String)] = [
        ("tiny",        "Tiny",        "~75 MB · fastest · lowest accuracy"),
        ("base",        "Base",        "~145 MB · faster · decent accuracy"),
        ("small",       "Small",       "~480 MB · balanced (recommended)"),
        ("large-v3_turbo", "Large v3 Turbo", "~1.5 GB · slowest · best accuracy"),
    ]
    static let defaultModel = "base"

    /// Carga en memoria un modelo YA DESCARGADO para que la primera nota de voz sea instantánea. Best-effort,
    /// al arrancar. Deliberadamente NO dispara aquí una descarga de primer uso — bajar en silencio un modelo de
    /// cientos de MB al arrancar la app sorprendería a usuarios con conexiones lentas/medidas; esa descarga ocurre
    /// de forma perezosa en la primera nota de voz (con el estado "Descargando modelo…").
    func prewarm(model: String) async {
        let id = model.isEmpty ? Self.defaultModel : model
        guard Self.isModelReady(id) else { return }
        _ = try? await pipeline(for: id)
    }

    /// Indica si los pesos CoreML del modelo están realmente en disco (no solo una carpeta creada a media descarga).
    /// Se usa para (a) saltar el prewarm de arranque en modelos no descargados y (b) mostrar "Descargando modelo…".
    nonisolated static func isModelReady(_ model: String) -> Bool {
        let id = model.isEmpty ? defaultModel : model
        guard let base = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: false) else { return false }
        let dir = base.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let folder = entries.first(where: { $0.hasPrefix("openai_whisper-\(id)") }) else { return false }
        // Exigir los pesos reales: una descarga interrumpida deja solo metadatos (generation_config.json).
        let modelDir = dir.appendingPathComponent(folder)
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0).path)
        }
    }

    /// Transcribe un archivo de audio por completo en el dispositivo. `model` es un nombre de modelo de WhisperKit (ver `models`).
    /// `vocabulary` (palabras/nombres de contexto) sesga el reconocimiento vía prompt tokens de Whisper.
    /// Entrada pública: serializa las decodificaciones sobre el pipeline compartido (ver `serialTail`).
    func transcribe(audioURL: URL, model: String, language: String?, vocabulary: String) async throws -> String {
        let previous = serialTail
        let job = Task<String, Error> {
            _ = await previous.value   // esperar cualquier decodificación en curso antes de tocar el WhisperKit compartido
            return try await self.performTranscribe(audioURL: audioURL, model: model, language: language, vocabulary: vocabulary)
        }
        serialTail = Task { _ = try? await job.value }   // la siguiente llamada se encadena tras esta
        return try await job.value
    }

    private func performTranscribe(audioURL: URL, model: String, language: String?, vocabulary: String) async throws -> String {
        let wk = try await pipeline(for: model.isEmpty ? Self.defaultModel : model)
        var opts = DecodingOptions()
        opts.task = .transcribe
        opts.skipSpecialTokens = true
        opts.withoutTimestamps = true
        // VELOCIDAD: dividir el audio largo en los silencios (VAD por energía) y decodificar los trozos en paralelo
        // (concurrentWorkerCount por defecto es 16). Los clips cortos quedan en un solo trozo → sin overhead; las
        // subidas largas se transcriben mucho más rápido. El modelo se carga una vez y se reutiliza (ver `pipeline`).
        opts.chunkingStrategy = .vad
        if let language, !language.isEmpty {
            opts.language = language          // idioma explícito del audio
            opts.detectLanguage = false
        } else {
            opts.detectLanguage = true        // "autodetección"
        }
        // Sesgar hacia las palabras/nombres de contexto del usuario (misma idea que el `prompt` de la nube):
        // codificarlos como prompt tokens de Whisper. WhisperKit además quita tokens especiales y limita la longitud internamente.
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty, let tok = wk.tokenizer {
            let ids = tok.encode(text: " " + vocab).filter { $0 < tok.specialTokens.specialTokenBegin }
            if !ids.isEmpty {
                opts.promptTokens = Array(ids.suffix(200))
                opts.usePrefillPrompt = true
            }
        }
        let results = try await wk.transcribe(audioPath: audioURL.path, decodeOptions: opts)
        return results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Recuerda un id de modelo que falló al cargar → el id al que se hizo fallback, para no reintentar la
    /// descarga fallida en cada transcripción posterior.
    private var fallbackFor: [String: String] = [:]

    private func pipeline(for model: String) async throws -> WhisperKit {
        let effective = fallbackFor[model] ?? model
        if let pipe, loadedModel == effective { return pipe }
        let wk: WhisperKit
        do {
            wk = try await WhisperKit(WhisperKitConfig(model: effective))   // descarga el modelo en el primer uso
            loadedModel = effective
        } catch {
            // Un id de modelo malo/no disponible (o una descarga fallida de esa variante) no debería romper todas
            // las transcripciones — hacer fallback al modelo por defecto y recordarlo (sin repetir descargas fallidas).
            guard effective != Self.defaultModel else { throw error }
            wk = try await WhisperKit(WhisperKitConfig(model: Self.defaultModel))
            loadedModel = Self.defaultModel
            fallbackFor[model] = Self.defaultModel
        }
        pipe = wk
        Self.pipelineReady = true
        return wk
    }
}
