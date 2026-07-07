import SwiftUI
import AppKit

/// Onboarding de primer arranque. Explica qué hace Klip y — importante para privacidad / revisión del App
/// Store — divulga que mantiene un historial local del portapapeles y que nunca envía nada fuera del Mac salvo
/// que el usuario añada una clave de IA para transcripción de voz. Se muestra una vez (Settings.hasSeenWelcome).
struct WelcomeView: View {
    @ObservedObject var settings = Settings.shared   // re-localizar en vivo + mostrar los atajos actuales
    var onStart: () -> Void

    private var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 14) {
            if let logo = appLogo {
                Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 68, height: 68)
            }
            Text(L10n.t("welcome.title")).font(.title2).bold()
            Text(L10n.t("welcome.tagline"))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 13) {
                row("doc.on.clipboard", L10n.t("welcome.history.title"), L10n.t("welcome.history.body"))
                row("lock.shield", L10n.t("welcome.privacy.title"), L10n.t("welcome.privacy.body"))
                row("keyboard", L10n.t("welcome.shortcuts.title"), shortcutsLine)
                row("mic", L10n.t("welcome.voice.title"), L10n.t("welcome.voice.body"))
            }
            .padding(.top, 4)

            Spacer(minLength: 8)
            Button(L10n.t("welcome.start")) { onStart() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text(L10n.t("welcome.prefsHint"))
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 440, height: 580)
    }

    private var shortcutsLine: String {
        [settings.combo, settings.voiceCombo, settings.captureCombo, settings.uploadCombo]
            .map { $0.displayString }.joined(separator: "   ·   ")
    }

    private func row(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.tint)
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
