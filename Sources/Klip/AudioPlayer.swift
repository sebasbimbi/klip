import Foundation
import AVFoundation

/// Reproductor simple para escuchar las notas de voz guardadas (una a la vez).
/// `playingFileName` permite a la UI mostrar el botón ▶/⏹ en el ítem que se está reproduciendo;
/// `elapsed`/`total` alimentan la barra de progreso de la fila en reproducción.
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    @Published private(set) var playingFileName: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func isPlaying(_ fileName: String) -> Bool { playingFileName == fileName }

    /// Duración (segundos) de un audio local, sin reproducirlo. nil si no se puede leer.
    static func duration(of url: URL) -> Double? {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return p.duration > 0 ? p.duration : nil
    }

    /// Alterna: si ese archivo ya se está reproduciendo, lo detiene; si no, lo reproduce (deteniendo cualquier otro).
    func toggle(fileName: String) {
        if playingFileName == fileName { stop() } else { play(fileName: fileName) }
    }

    func play(fileName: String) {
        stop()
        let url = Storage.shared.audioURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        guard p.play() else { return }
        player = p
        playingFileName = fileName
        elapsed = 0
        total = p.duration
        startTicker()
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        if playingFileName != nil { playingFileName = nil }
        elapsed = 0; total = 0
    }

    /// Detiene solo si ese archivo resulta estar en reproducción (p. ej. al borrarlo del historial).
    func stopIfPlaying(_ fileName: String) {
        if playingFileName == fileName { stop() }
    }

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            self.elapsed = p.currentTime
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        clear(if: player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        clear(if: player)
    }

    /// Limpia solo si el que terminó sigue siendo el reproductor actual (evita cortar una reproducción nueva).
    private func clear(if finished: AVAudioPlayer) {
        DispatchQueue.main.async { [weak self] in
            guard let self, finished === self.player else { return }
            self.stop()
        }
    }
}
