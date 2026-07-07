import Foundation
import Vision
import AppKit

/// Reconocimiento de texto en imágenes usando el framework Vision (en el dispositivo).
enum OCR {
    static func recognizeText(in image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return recognizeText(in: cg)
    }

    /// Tokens comunes de código que la corrección de idioma tiende a "arreglar" hacia prosa; listarlos como
    /// palabras personalizadas los mantiene intactos aunque la corrección esté apagada.
    private static let codeWords = ["func", "let", "var", "const", "async", "await", "return", "nil",
                                    "null", "void", "import", "export", "class", "struct", "enum",
                                    "true", "false", "=>", "->", "==", "!=", "&&", "||"]

    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // APAGADO para código: la corrección de idioma reescribe símbolos/identificadores como prosa (== → =,
        // nombres → palabras de diccionario, puntuación perdida). Apagado es más preciso para código y más rápido.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "es-ES"]
        request.automaticallyDetectsLanguage = false   // especificamos los idiomas → saltar la pasada de detección (más rápido)
        request.customWords = codeWords
        request.minimumTextHeight = 0   // no saltarse fuentes diminutas de terminal/logs

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let observations = request.results else { return "" }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
