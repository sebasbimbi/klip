import SwiftUI
import AppKit

/// Guía de uso: atajos de Klip + atajos de captura de macOS + cómo usar.
struct GuideView: View {
    @ObservedObject var settings = Settings.shared

    private struct Row: Identifiable { let id = UUID(); let keys: String; let what: String }

    private var klipShortcuts: [Row] {
        [
            Row(keys: settings.combo.displayString, what: "Abrir / cerrar el historial"),
            Row(keys: settings.voiceCombo.displayString, what: "Grabar nota de voz (pulsa otra vez para detener)"),
            Row(keys: "↑ ↓", what: "Moverte por la lista"),
            Row(keys: "↩", what: "Elegir el elemento (copiar / pegar)"),
            Row(keys: "⌘1 … ⌘9", what: "Elegir directamente el elemento 1–9"),
            Row(keys: "Esc", what: "Cerrar el panel"),
            Row(keys: "⌘,", what: "Abrir Preferencias")
        ]
    }

    private let macShortcuts: [Row] = [
        Row(keys: "⌘⇧3", what: "Captura de TODA la pantalla (se guarda en el escritorio)"),
        Row(keys: "⌘⇧4", what: "Captura de una ZONA que seleccionas"),
        Row(keys: "⌘⇧5", what: "Herramientas de captura y grabación de pantalla"),
        Row(keys: "⌘⇧⌃4", what: "Captura de zona directo AL PORTAPAPELES (aparece en Klip)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section("⌨️ Atajos de Klip", klipShortcuts)
                section("📸 Atajos de captura de macOS", macShortcuts,
                        footer: "Klip guarda las capturas que copies. Usa ⌘⇧⌃4 para copiar una zona directo al portapapeles.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("💡 Cómo se usa").font(.headline)
                    bullet("Copia texto o imágenes con normalidad: aparecen en el historial.")
                    bullet("Pulsa \(settings.combo.displayString) y haz clic (o Enter) para volver a pegar algo.")
                    bullet("Las contraseñas/tokens se detectan y guardan aparte, enmascarados (filtro 🔑).")
                    bullet("Graba notas de voz y se transcriben a texto con OpenAI.")
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let logo = HistoryView.appLogo {
                Image(nsImage: logo).resizable().frame(width: 48, height: 48)
            }
            VStack(alignment: .leading) {
                Text("Guía de Klip").font(.title2).bold()
                Text("v\(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, _ rows: [Row], footer: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: 12) {
                    Text(r.keys)
                        .font(.system(.body, design: .monospaced)).bold()
                        .frame(width: 90, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    Text(r.what).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.system(size: 13))
        }
    }
}
