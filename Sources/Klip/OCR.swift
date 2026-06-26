import Foundation
import Vision
import AppKit

/// Text recognition in images using the Vision framework (on-device).
enum OCR {
    static func recognizeText(in image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return recognizeText(in: cg)
    }

    /// Common code tokens that language correction tends to "fix" into prose; listing them as custom
    /// words keeps them intact even though correction is off.
    private static let codeWords = ["func", "let", "var", "const", "async", "await", "return", "nil",
                                    "null", "void", "import", "export", "class", "struct", "enum",
                                    "true", "false", "=>", "->", "==", "!=", "&&", "||"]

    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // OFF for code: language correction rewrites symbols/identifiers into prose (== → =, names →
        // dictionary words, dropped punctuation). Off is both more accurate for code and faster.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "es-ES"]
        request.automaticallyDetectsLanguage = false   // we specify the languages → skip the detection pass (faster)
        request.customWords = codeWords
        request.minimumTextHeight = 0   // don't skip tiny terminal/log fonts

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
