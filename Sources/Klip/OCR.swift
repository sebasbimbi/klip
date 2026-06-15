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

    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US"]

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
