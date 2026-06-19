import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Puente ObservableObject para una API key (OpenAI o Gemini), guardada en archivo local 0600.
@MainActor
final class APIKeyModel: ObservableObject {
    let key: SecretStore.Key
    @Published private(set) var isConfigured = false
    @Published private(set) var last4: String?
    @Published var errorMessage: String?
    @Published var savedOK = false

    init(_ key: SecretStore.Key = .openai) { self.key = key; refresh() }

    func refresh() {
        isConfigured = SecretStore.hasKey(key)
        last4 = SecretStore.last4(key)
    }

    @discardableResult
    func save(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "No se detectó ninguna clave. Pega el texto y vuelve a intentarlo."
            savedOK = false
            return false
        }
        do {
            let ok = try SecretStore.set(trimmed, key)   // escribe y RELEE para confirmar
            if ok {
                errorMessage = nil; savedOK = true
            } else {
                errorMessage = "La clave no se pudo confirmar tras guardarla."; savedOK = false
            }
            refresh()
            return ok
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
            savedOK = false
            refresh()
            return false
        }
    }

    func delete() {
        SecretStore.delete(key); errorMessage = nil; savedOK = false
        refresh()
    }
}

/// Ventana de Preferencias de Klip.
struct PreferencesView: View {
    @ObservedObject var settings = Settings.shared
    var onHotKeyChange: (KeyCombo) -> Void
    var onVoiceHotKeyChange: (KeyCombo) -> Void
    var onCaptureHotKeyChange: (KeyCombo) -> Void
    var onMaxItemsChange: () -> Void

    @StateObject private var apiKey = APIKeyModel(.openai)
    @StateObject private var geminiKey = APIKeyModel(.gemini)
    @State private var draftKey = ""
    @State private var showKey = false
    @State private var draftGeminiKey = ""
    @State private var showGeminiKey = false
    @State private var launchAtLogin = LoginItem.shared.isEnabledOrPending
    @State private var loginError: String?
    @State private var accessibilityGranted = Paster.hasAccessibilityPermission

    private let models = ["gpt-4o-mini-transcribe", "whisper-1"]
    // Modelos de Gemini. Los alias "-latest" evitan 404 por deprecación; se incluyen también
    // versiones fijadas para quien quiera estabilidad de comportamiento.
    private let geminiModels = ["gemini-flash-latest", "gemini-flash-lite-latest",
                                "gemini-pro-latest", "gemini-2.5-flash", "gemini-2.5-pro"]
    // Dictation/audio languages passed to the transcription provider (endonyms). "" = auto-detect.
    private let dictationLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"),
        ("it", "Italiano"), ("pt", "Português"), ("zh", "中文"), ("ja", "日本語"),
        ("ko", "한국어"), ("ru", "Русский"), ("nl", "Nederlands"), ("hi", "हिन्दी")
    ]

    private var appLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            aboutHeader
            Divider()
            form
        }
        .frame(width: 500, height: 700)
        .onAppear {
            apiKey.refresh(); geminiKey.refresh()
            launchAtLogin = LoginItem.shared.isEnabledOrPending
            accessibilityGranted = Paster.hasAccessibilityPermission
        }
    }

    private var aboutHeader: some View {
        HStack(spacing: 12) {
            if let logo = appLogo {
                Image(nsImage: logo).resizable().frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Klip").font(.title2).bold()
                Text("v\(AppInfo.version) · \(L10n.t("app.tagline"))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let u = URL(string: AppInfo.repoURL) {
                        Link(label: "chevron.left.forwardslash.chevron.right", text: "GitHub", url: u)
                    }
                    if let u = URL(string: AppInfo.issuesURL) {
                        Link(label: "lightbulb", text: L10n.t("prefs.suggestions"), url: u)
                    }
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(16)
    }

    private var form: some View {
        Form {
            Section(L10n.t("prefs.lang.section")) {
                Picker(L10n.t("prefs.lang.label"), selection: $settings.uiLanguage) {
                    ForEach(L10n.supported, id: \.code) { Text($0.name).tag($0.code) }
                }
            }

            Section(L10n.t("prefs.general")) {
                Toggle(L10n.t("prefs.openAtLogin"), isOn: Binding(
                    get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle(L10n.t("prefs.autopaste"), isOn: $settings.autoPaste)
                if settings.autoPaste && !accessibilityGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(L10n.t("prefs.needAccessibility")).font(.caption)
                        Button(L10n.t("prefs.grant")) { Paster.ensureAccessibilityPermission(prompt: true) }.font(.caption)
                    }
                }
                Stepper(String(format: L10n.t("prefs.maxItems"), settings.maxItems),
                        value: $settings.maxItems, in: 20...1000, step: 10)
                    .onChange(of: settings.maxItems) { _, _ in onMaxItemsChange() }
            }

            Section(L10n.t("prefs.shortcuts")) {
                HStack { Text(L10n.t("prefs.sc.show")); Spacer()
                    HotKeyField(combo: $settings.combo, onChange: onHotKeyChange) }
                HStack { Text(L10n.t("prefs.sc.voice")); Spacer()
                    HotKeyField(combo: $settings.voiceCombo, onChange: onVoiceHotKeyChange) }
                HStack { Text(L10n.t("prefs.sc.capture")); Spacer()
                    HotKeyField(combo: $settings.captureCombo, onChange: onCaptureHotKeyChange) }
                Text(L10n.t("prefs.sc.hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("prefs.voice.section")) {
                Picker(L10n.t("prefs.provider"), selection: $settings.aiProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Google Gemini").tag("gemini")
                }
                .pickerStyle(.segmented)
                if settings.aiProvider == "openai" {
                    Picker(L10n.t("prefs.model"), selection: $settings.transcriptionModel) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    Picker(L10n.t("prefs.model"), selection: $settings.geminiModel) {
                        ForEach(geminiModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker(L10n.t("prefs.audioLang"), selection: $settings.transcriptionLanguage) {
                    Text(L10n.t("lang.auto")).tag("")
                    ForEach(dictationLanguages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Text(settings.aiProvider == "gemini"
                     ? L10n.t("prefs.voice.useGemini")
                     : L10n.t("prefs.voice.useOpenAI"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if settings.aiProvider == "openai" {
            Section(L10n.t("prefs.openai.section")) {
                keyStatus(apiKey)
                HStack {
                    if showKey {
                        TextField("sk-…", text: $draftKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveOpenAI() }
                    } else {
                        SecureField("sk-…", text: $draftKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveOpenAI() }
                    }
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                HStack {
                    Button(L10n.t("common.save")) { saveOpenAI() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.t("common.delete"), role: .destructive) { apiKey.delete() }.disabled(!apiKey.isConfigured)
                    if apiKey.savedOK { Label(L10n.t("prefs.saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }
                if let err = apiKey.errorMessage { Text(err).font(.caption).foregroundStyle(.red) }
            }
            }

            if settings.aiProvider == "gemini" {
            Section(L10n.t("prefs.gemini.section")) {
                keyStatus(geminiKey)
                HStack {
                    if showGeminiKey {
                        TextField("AIza…", text: $draftGeminiKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveGemini() }
                    } else {
                        SecureField("AIza…", text: $draftGeminiKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveGemini() }
                    }
                    Button { showGeminiKey.toggle() } label: { Image(systemName: showGeminiKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                HStack {
                    Button(L10n.t("common.save")) { saveGemini() }
                        .disabled(draftGeminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.t("common.delete"), role: .destructive) { geminiKey.delete() }.disabled(!geminiKey.isConfigured)
                    if geminiKey.savedOK { Label(L10n.t("prefs.saved"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }
                if let err = geminiKey.errorMessage { Text(err).font(.caption).foregroundStyle(.red) }
                Text(L10n.t("prefs.gemini.help"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            }

            Section(L10n.t("prefs.privacy.section")) {
                Toggle(L10n.t("prefs.privacy.toggle"), isOn: $settings.ignoreSensitive)
                Text(L10n.t("prefs.privacy.info"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("prefs.excluded.section")) {
                if settings.excludedBundleIDs.isEmpty {
                    Text(L10n.t("prefs.excluded.none"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(size: 12)); Spacer()
                        Button(role: .destructive) { settings.removeExcludedApp(id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { pickApp() } label: { Label(L10n.t("prefs.excluded.add"), systemImage: "plus") }
            }
        }
        .formStyle(.grouped)
    }

    /// Fuerza al campo enfocado a confirmar su edición ANTES de leer el binding.
    /// SwiftUI no siempre propaga el texto pegado a `draftKey` antes de que corra la acción del
    /// botón (campo dentro de Form .grouped, sigue siendo first responder): al terminar la edición
    /// del NSTextField, el valor en curso se vuelca al binding. Sin esto, `save` leía el valor viejo.
    private func commitFocusedField() {
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)   // endEditing → vuelca el texto al binding
        }
    }

    private func saveOpenAI() {
        commitFocusedField()
        // Tras volcar el binding en este ciclo de runloop, leer el valor ya actualizado.
        DispatchQueue.main.async {
            if apiKey.save(draftKey) { draftKey = ""; showKey = false }
        }
    }

    private func saveGemini() {
        commitFocusedField()
        DispatchQueue.main.async {
            if geminiKey.save(draftGeminiKey) { draftGeminiKey = ""; showGeminiKey = false }
        }
    }

    @ViewBuilder
    private func keyStatus(_ model: APIKeyModel) -> some View {
        HStack(spacing: 6) {
            if model.isConfigured {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Clave configurada")
                if let l4 = model.last4 {
                    Text("••••\(l4)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Sin clave configurada").foregroundStyle(.secondary)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        switch LoginItem.shared.toggle() {
        case .success:
            launchAtLogin = LoginItem.shared.isEnabledOrPending; loginError = nil
        case .failure(let err):
            if case .requiresApproval = err { LoginItem.shared.openSystemSettings() }
            loginError = err.localizedDescription
            launchAtLogin = LoginItem.shared.isEnabledOrPending
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            settings.addExcludedApp(id)
        }
    }
}

/// Enlace con icono que abre el navegador.
private struct Link: View {
    let label: String
    let text: String
    let url: URL
    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 3) { Image(systemName: label); Text(text) }
        }
        .buttonStyle(.link)
    }
}
