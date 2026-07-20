import AppKit

/// Interface sound effects for user actions (copy, capture, record, delete…).
///
/// The cues are rendered from the "core" kit of raphaelsalaja/audio
/// (https://github.com/raphaelsalaja/audio, MIT © 2026 Raphael Salaja), a synthesis library whose
/// kits define each sound as an oscillator+envelope patch rather than an audio file.
/// Tools/bake-sounds.mjs renders them once to the WAVs in Resources/Sounds, and build.sh ships
/// that folder into the app bundle exactly like AppIcon.icns. A bare `swift build` binary has no
/// bundle → play() degrades to a silent no-op.
@MainActor
enum SoundFX {
    enum Event: String {
        case copy, success, save, error, warning, delete, pop
        case toggleOn = "toggle-on"
        case toggleOff = "toggle-off"
        case recordStart = "loading-start"
        case recordStop = "loading-end"
    }

    /// One gesture can reach two sound sites (OCR: the history add + the pasteboard notification;
    /// editor save: the save toast + the copy-back). Within this window the same event plays once,
    /// and success/save also swallow the copy tick they imply.
    private static let dedupeWindow: TimeInterval = 0.25

    private static var cache: [Event: NSSound] = [:]
    private static var lastRequested: [Event: Date] = [:]

    /// Plays the copy cue for every pasteboard write made through the app (.klipDidCopy).
    /// External copies (⌘C anywhere) are cued from ClipboardManager when they are captured.
    static func activate() {
        NotificationCenter.default.addObserver(forName: .klipDidCopy, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { play(.copy) }
        }
    }

    static func play(_ event: Event) {
        guard Settings.shared.soundEffects else { return }
        let now = Date()
        if let last = lastRequested[event], now.timeIntervalSince(last) < dedupeWindow { return }
        lastRequested[event] = now
        if event == .success || event == .save { lastRequested[.copy] = now }
        guard let sound = sound(for: event) else { return }
        if sound.isPlaying { sound.stop() }   // rapid repeat: restart instead of dropping it
        sound.play()
    }

    /// Failure cue. Falls back to the system beep when sounds are off — the beeps this replaced
    /// were load-bearing ("without a cue the user pastes stale clipboard content").
    static func error() {
        if Settings.shared.soundEffects { play(.error) } else { NSSound.beep() }
    }

    /// Attention cue for partial failures (skipped files, silence while recording). Same fallback.
    static func warning() {
        if Settings.shared.soundEffects { play(.warning) } else { NSSound.beep() }
    }

    private static func sound(for event: Event) -> NSSound? {
        if let cached = cache[event] { return cached }
        guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "wav",
                                        subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        sound.volume = 0.7   // master trim; the kit's per-sound gains carry the relative balance
        cache[event] = sound
        return sound
    }
}
