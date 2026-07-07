import AppKit
import Carbon.HIToolbox
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let recentsMenu = NSMenu()
    private static let recentsDF: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale.current; f.dateFormat = "dd MMM HH:mm"; return f
    }()
    private let manager = ClipboardManager()
    private var panelController: PanelController!
    private var snapController: SnapController!
    private var hotKey: HotKey?
    private var voiceHotKey: HotKey?
    private var captureHotKey: HotKey?
    private var uploadHotKey: HotKey?
    private var textCaptureHotKey: HotKey?
    private var lastGoodCombo = Settings.shared.combo
    private var lastGoodVoiceCombo = Settings.shared.voiceCombo
    private var lastGoodCaptureCombo = Settings.shared.captureCombo
    private var lastGoodUploadCombo = Settings.shared.uploadCombo
    private var lastGoodTextCaptureCombo = Settings.shared.textCaptureCombo
    private var prefsController: PreferencesWindowController?
    private var launchItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klip")?
                .withSymbolConfiguration(cfg)
        }
        installMainMenu()
        buildMenu()
        panelController = PanelController(manager: manager, statusItem: statusItem)
        panelController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        snapController = SnapController(manager: manager)
        snapController.onCaptured = { [weak self] in self?.panelController.show() }
        panelController.onCaptureAnnotate = { [weak self] in self?.snapController.start() }
        manager.start()
        setupHotKeys()
        maybeEnableLoginOnce()
        // On-device es el valor por defecto: precargar (y, si es el primer arranque, descargar) el modelo ahora
        // para que la primera nota de voz se transcriba de inmediato en vez de esperar una carga/descarga en frío.
        if Settings.shared.aiProvider == "local" {
            let m = Settings.shared.localModel
            Task.detached(priority: .utility) { await LocalTranscriber.shared.prewarm(model: m) }
        }
        // Saltar a main explícitamente para que buildMenu() (@MainActor) sea seguro sin importar dónde se mute uiLanguage.
        Settings.shared.$uiLanguage.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.buildMenu() }.store(in: &cancellables)
        // Onboarding de primer arranque (monitoreo del portapapeles + aviso de privacidad). Diferido para que nunca frene el arranque.
        if !Settings.shared.hasSeenWelcome {
            DispatchQueue.main.async { [weak self] in self?.panelController.showWelcome() }
        }
    }

    // Una app accesoria (.accessory) no tiene menú principal, así que los campos de texto de SwiftUI
    // no reciben ⌘X/⌘C/⌘V/⌘A (no hay menú "Edit" que enrute esos atajos por la responder
    // chain). Instalamos un menú principal mínimo con un menú Edit estándar.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // Menú de la app (necesario para que el menú Edit aparezca como el segundo).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Menú Edit con los atajos estándar (target nil → responder chain).
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "\(L10n.t("menu.show"))   \(Settings.shared.combo.displayString)",
                     action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "\(L10n.t("rec.record"))   \(Settings.shared.voiceCombo.displayString)",
                     action: #selector(startVoice), keyEquivalent: "")
        menu.addItem(withTitle: "\(L10n.t("menu.capture"))   \(Settings.shared.captureCombo.displayString)",
                     action: #selector(startCapture), keyEquivalent: "")
        menu.addItem(withTitle: "\(L10n.t("menu.captureText"))   \(Settings.shared.textCaptureCombo.displayString)",
                     action: #selector(startTextCapture), keyEquivalent: "")
        menu.addItem(withTitle: "\(L10n.t("act.upload"))   \(Settings.shared.uploadCombo.displayString)",
                     action: #selector(startUpload), keyEquivalent: "")
        menu.addItem(.separator())
        let recents = NSMenuItem(title: L10n.t("menu.recents"), action: nil, keyEquivalent: "")
        recentsMenu.delegate = self
        recents.submenu = recentsMenu
        menu.addItem(recents)
        menu.addItem(.separator())
        let prefs = menu.addItem(withTitle: L10n.t("menu.prefs"), action: #selector(openPreferences), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        let launch = NSMenuItem(title: L10n.t("menu.login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        menu.addItem(launch); self.launchItem = launch
        menu.addItem(withTitle: L10n.t("menu.autopaste"), action: #selector(enableAutoPaste), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("act.guide"), action: #selector(showGuideMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.export"), action: #selector(exportBackup), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("menu.import"), action: #selector(importBackup), keyEquivalent: "")
        menu.addItem(withTitle: L10n.t("menu.clear"), action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { if $0.target == nil { $0.target = self } }
        menu.delegate = self   // menuNeedsUpdate refresca el checkmark de abrir-al-iniciar-sesión desde el estado actual de SMAppService
        statusItem.menu = menu
    }

    private func makePanelHotKey(_ c: KeyCombo) {
        hotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 1) { [weak self] in
            self?.panelController.toggle()
        }
    }
    private func makeVoiceHotKey(_ c: KeyCombo) {
        voiceHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 2) { [weak self] in
            self?.panelController.toggleVoiceRecording()
        }
    }
    private func makeCaptureHotKey(_ c: KeyCombo) {
        captureHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 3) { [weak self] in
            self?.snapController.start()
        }
    }
    private func makeUploadHotKey(_ c: KeyCombo) {
        uploadHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 4) { [weak self] in
            self?.panelController.uploadAudio()
        }
    }
    private func makeTextCaptureHotKey(_ c: KeyCombo) {
        textCaptureHotKey = HotKey(keyCode: c.keyCode, modifiers: c.carbonModifiers, id: 5) { [weak self] in
            self?.snapController.startTextCapture()
        }
    }

    private func registerHotKey(_ kind: ShortcutKind, _ c: KeyCombo) {
        switch kind {
        case .panel: makePanelHotKey(c)
        case .voice: makeVoiceHotKey(c)
        case .capture: makeCaptureHotKey(c)
        case .upload: makeUploadHotKey(c)
        case .textCapture: makeTextCaptureHotKey(c)
        }
    }
    private func hotKeyLive(_ kind: ShortcutKind) -> Bool {
        switch kind {
        case .panel: return hotKey != nil
        case .voice: return voiceHotKey != nil
        case .capture: return captureHotKey != nil
        case .upload: return uploadHotKey != nil
        case .textCapture: return textCaptureHotKey != nil
        }
    }
    /// Tras mover un atajo VIVO, verificar que realmente se registró; si el SO rechazó el combo (otra
    /// app lo posee) caer a la primera sugerencia registrable, para que el dedup nunca persista un combo muerto.
    private func ensureLiveRegistered(_ kind: ShortcutKind, avoiding taken: [KeyCombo], commit: (KeyCombo) -> Void) {
        guard !hotKeyLive(kind) else { return }
        for cand in KeyCombo.suggestions where !taken.contains(cand) {
            registerHotKey(kind, cand)
            if hotKeyLive(kind) { commit(cand); return }
        }
    }

    /// Una migración (o una edición manual) puede dejar dos de los tres atajos en el MISMO combo. Carbon registra
    /// cada uno bajo un id distinto, así que AMBOS tienen éxito y una pulsación dispara dos acciones. Romper duplicados antes
    /// de registrar: conservar el combo del panel, mover voz/captura de cualquier choque a una sugerencia libre (o al default).
    private func deduplicateShortcuts() {
        let s = Settings.shared
        func free(_ taken: [KeyCombo], _ fallback: KeyCombo) -> KeyCombo {
            if !taken.contains(fallback) { return fallback }
            return KeyCombo.suggestions.first { !taken.contains($0) } ?? fallback
        }
        // Re-registrar solo cuando ya está vivo (es decir, cuando se llama OTRA VEZ tras la recuperación de arranque) — en la primera
        // llamada las llamadas make*HotKey de justo después se encargan del registro.
        if s.voiceCombo == s.combo {
            let fixed = free([s.combo], .defaultVoiceCombo); s.voiceCombo = fixed; lastGoodVoiceCombo = fixed
            if voiceHotKey != nil {
                makeVoiceHotKey(fixed)
                ensureLiveRegistered(.voice, avoiding: [s.combo]) { s.voiceCombo = $0; lastGoodVoiceCombo = $0 }
            }
        }
        if s.captureCombo == s.combo || s.captureCombo == s.voiceCombo {
            let fixed = free([s.combo, s.voiceCombo], .defaultCaptureCombo); s.captureCombo = fixed; lastGoodCaptureCombo = fixed
            if captureHotKey != nil {
                makeCaptureHotKey(fixed)
                ensureLiveRegistered(.capture, avoiding: [s.combo, s.voiceCombo]) { s.captureCombo = $0; lastGoodCaptureCombo = $0 }
            }
        }
        if s.uploadCombo == s.combo || s.uploadCombo == s.voiceCombo || s.uploadCombo == s.captureCombo {
            let fixed = free([s.combo, s.voiceCombo, s.captureCombo], .defaultUploadCombo); s.uploadCombo = fixed; lastGoodUploadCombo = fixed
            if uploadHotKey != nil {
                makeUploadHotKey(fixed)
                ensureLiveRegistered(.upload, avoiding: [s.combo, s.voiceCombo, s.captureCombo]) { s.uploadCombo = $0; lastGoodUploadCombo = $0 }
            }
        }
        let used = [s.combo, s.voiceCombo, s.captureCombo, s.uploadCombo]
        if used.contains(s.textCaptureCombo) {
            let fixed = free(used, .defaultTextCaptureCombo); s.textCaptureCombo = fixed; lastGoodTextCaptureCombo = fixed
            if textCaptureHotKey != nil {
                makeTextCaptureHotKey(fixed)
                ensureLiveRegistered(.textCapture, avoiding: used) { s.textCaptureCombo = $0; lastGoodTextCaptureCombo = $0 }
            }
        }
    }

    private func setupHotKeys() {
        deduplicateShortcuts()
        makePanelHotKey(Settings.shared.combo)
        makeVoiceHotKey(Settings.shared.voiceCombo)
        makeCaptureHotKey(Settings.shared.captureCombo)
        makeUploadHotKey(Settings.shared.uploadCombo)
        makeTextCaptureHotKey(Settings.shared.textCaptureCombo)
        // Si una combinación persistida choca con otra al arrancar (HotKey.init devuelve nil), el
        // atajo quedaría muerto toda la sesión. Recuperar con su atajo por defecto para que no se pierda.
        if hotKey == nil, Settings.shared.combo != .defaultCombo {
            Settings.shared.combo = .defaultCombo; lastGoodCombo = .defaultCombo; makePanelHotKey(.defaultCombo)
        }
        if voiceHotKey == nil, Settings.shared.voiceCombo != .defaultVoiceCombo {
            Settings.shared.voiceCombo = .defaultVoiceCombo; lastGoodVoiceCombo = .defaultVoiceCombo; makeVoiceHotKey(.defaultVoiceCombo)
        }
        if captureHotKey == nil, Settings.shared.captureCombo != .defaultCaptureCombo {
            Settings.shared.captureCombo = .defaultCaptureCombo; lastGoodCaptureCombo = .defaultCaptureCombo; makeCaptureHotKey(.defaultCaptureCombo)
        }
        // Si incluso el atajo de captura por defecto choca (p. ej. otra app ya lo tomó), probar las combinaciones
        // sugeridas para que la captura no quede inerte sin que el usuario lo sepa.
        if captureHotKey == nil {
            for s in KeyCombo.suggestions where s != Settings.shared.combo && s != Settings.shared.voiceCombo {
                makeCaptureHotKey(s)
                if captureHotKey != nil {
                    Settings.shared.captureCombo = s; lastGoodCaptureCombo = s
                    // Diferir el modal: un runModal síncrono aquí frenaría el resto del arranque.
                    Task { @MainActor in self.showAlert(L10n.t("hotkey.capture.changed.title"), L10n.t("hotkey.capture.changed.info")) }
                    break
                }
            }
        }
        // Subir también es accesible desde la barra de menús y el botón del panel de historial, así que un atajo muerto aquí
        // no es crítico: recuperar en silencio (default → sugerencia libre) sin interrumpir al usuario con una alerta.
        if uploadHotKey == nil, Settings.shared.uploadCombo != .defaultUploadCombo {
            Settings.shared.uploadCombo = .defaultUploadCombo; lastGoodUploadCombo = .defaultUploadCombo
            makeUploadHotKey(.defaultUploadCombo)
        }
        if uploadHotKey == nil {
            for s in KeyCombo.suggestions where s != Settings.shared.combo && s != Settings.shared.voiceCombo && s != Settings.shared.captureCombo {
                makeUploadHotKey(s)
                if uploadHotKey != nil { Settings.shared.uploadCombo = s; lastGoodUploadCombo = s; break }
            }
        }
        // La captura de texto (OCR) también es accesible desde la barra de menús, así que recuperar en silencio como subir.
        if textCaptureHotKey == nil, Settings.shared.textCaptureCombo != .defaultTextCaptureCombo {
            Settings.shared.textCaptureCombo = .defaultTextCaptureCombo; lastGoodTextCaptureCombo = .defaultTextCaptureCombo
            makeTextCaptureHotKey(.defaultTextCaptureCombo)
        }
        if textCaptureHotKey == nil {
            let taken = [Settings.shared.combo, Settings.shared.voiceCombo, Settings.shared.captureCombo, Settings.shared.uploadCombo]
            for s in KeyCombo.suggestions where !taken.contains(s) {
                makeTextCaptureHotKey(s)
                if textCaptureHotKey != nil { Settings.shared.textCaptureCombo = s; lastGoodTextCaptureCombo = s; break }
            }
        }
        // Si los atajos de panel/voz siguen muertos tras el reseteo al default (otra app posee globalmente
        // incluso el combo por defecto), avisar al usuario en vez de dejar un atajo silenciosamente inerte (diferido para
        // no bloquear el arranque).
        if hotKey == nil || voiceHotKey == nil {
            Task { @MainActor in NSSound.beep(); self.showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")) }
        }
        // Los bucles de recuperación por sugerencias de arriba pueden dejar un atajo sobre el combo de un hermano (no todos
        // excluyen a cada hermano). Ejecutar el dedup una vez más — ahora re-registra lo que mueve — para que ningún par de
        // atajos comparta un combo (lo que dispararía dos acciones con una pulsación).
        deduplicateShortcuts()
        // Reflejar cualquier remapeo de arranque en las etiquetas de atajos del menú.
        buildMenu()
    }

    private enum ShortcutKind { case panel, voice, capture, upload, textCapture }

    /// Carbon registra cada atajo bajo un id distinto, así que NO rechaza asignar el MISMO combo
    /// a dos de nuestros atajos — debemos detectarlo nosotros mismos.
    private func collidesWithOtherShortcut(_ combo: KeyCombo, _ kind: ShortcutKind) -> Bool {
        let s = Settings.shared
        let others: [KeyCombo]
        switch kind {
        case .panel:       others = [s.voiceCombo, s.captureCombo, s.uploadCombo, s.textCaptureCombo]
        case .voice:       others = [s.combo, s.captureCombo, s.uploadCombo, s.textCaptureCombo]
        case .capture:     others = [s.combo, s.voiceCombo, s.uploadCombo, s.textCaptureCombo]
        case .upload:      others = [s.combo, s.voiceCombo, s.captureCombo, s.textCaptureCombo]
        case .textCapture: others = [s.combo, s.voiceCombo, s.captureCombo, s.uploadCombo]
        }
        return others.contains(combo)
    }

    private func applyCaptureHotKey(_ combo: KeyCombo) {
        if collidesWithOtherShortcut(combo, .capture) {
            NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse"))
            Settings.shared.captureCombo = lastGoodCaptureCombo; buildMenu(); return
        }
        let ok: Bool
        if captureHotKey == nil { makeCaptureHotKey(combo); ok = (captureHotKey != nil) }   // estaba muerto: recrear
        else { ok = captureHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodCaptureCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.captureCombo = lastGoodCaptureCombo }
        buildMenu()
    }

    private func applyHotKey(_ combo: KeyCombo) {
        if collidesWithOtherShortcut(combo, .panel) {
            NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse"))
            Settings.shared.combo = lastGoodCombo; buildMenu(); return
        }
        let ok: Bool
        if hotKey == nil { makePanelHotKey(combo); ok = (hotKey != nil) }
        else { ok = hotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.combo = lastGoodCombo }   // colisión: revertir
        buildMenu()
    }

    private func applyVoiceHotKey(_ combo: KeyCombo) {
        if collidesWithOtherShortcut(combo, .voice) {
            NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse"))
            Settings.shared.voiceCombo = lastGoodVoiceCombo; buildMenu(); return
        }
        let ok: Bool
        if voiceHotKey == nil { makeVoiceHotKey(combo); ok = (voiceHotKey != nil) }
        else { ok = voiceHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodVoiceCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.voiceCombo = lastGoodVoiceCombo }
        buildMenu()
    }

    private func applyUploadHotKey(_ combo: KeyCombo) {
        if collidesWithOtherShortcut(combo, .upload) {
            NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse"))
            Settings.shared.uploadCombo = lastGoodUploadCombo; buildMenu(); return
        }
        let ok: Bool
        if uploadHotKey == nil { makeUploadHotKey(combo); ok = (uploadHotKey != nil) }
        else { ok = uploadHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodUploadCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.uploadCombo = lastGoodUploadCombo }
        buildMenu()
    }

    private func applyTextCaptureHotKey(_ combo: KeyCombo) {
        if collidesWithOtherShortcut(combo, .textCapture) {
            NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse"))
            Settings.shared.textCaptureCombo = lastGoodTextCaptureCombo; buildMenu(); return
        }
        let ok: Bool
        if textCaptureHotKey == nil { makeTextCaptureHotKey(combo); ok = (textCaptureHotKey != nil) }
        else { ok = textCaptureHotKey?.reRegister(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) == true }
        if ok { lastGoodTextCaptureCombo = combo }
        else { NSSound.beep(); showAlert(L10n.t("act.prefs"), L10n.t("hotkey.inuse")); Settings.shared.textCaptureCombo = lastGoodTextCaptureCombo }
        buildMenu()
    }

    private func maybeEnableLoginOnce() {
        let key = "didAutoEnableLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        LoginItem.shared.registerIfNeeded()
        // Marcar "hecho" solo cuando el registro realmente prendió. En el primer arranque la app puede estar translocada
        // (el registro falla); dejar el flag sin poner permite reintentar en un arranque posterior desde /Applications.
        if LoginItem.shared.isEnabledOrPending { UserDefaults.standard.set(true, forKey: key) }
        launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
    }

    // Submenú "Recientes": se reconstruye cada vez que se abre.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusItem.menu {   // la aprobación puede ocurrir en Ajustes del Sistema mientras corremos → reflejarla al abrir
            launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
            return
        }
        guard menu === recentsMenu else { return }
        menu.removeAllItems()
        let items = manager.items.sorted { $0.createdAt > $1.createdAt }.prefix(10)
        if items.isEmpty {
            let empty = NSMenuItem(title: L10n.t("menu.empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for it in items {
            let icon = it.isVoiceNote == true ? "🎙 " : (it.kind == .image ? "🖼 " : (it.isCredential == true ? "🔑 " : ""))
            let body: String
            if let nm = it.name, !nm.isEmpty { body = String(nm.prefix(45)) }   // nombre puesto por el usuario
            else if it.isCredential == true { body = CredentialDetector.masked(it.text ?? "") }
            else if it.isVoiceNote == true {
                // texto transcrito (evita un 🎙 doble); si aún no hay, usar la vista previa sin el emoji.
                let tx = (it.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                body = tx.isEmpty ? String(it.preview.drop(while: { $0 == "🎙" || $0 == " " }).prefix(45))
                                  : String(tx.prefix(45))
            }
            else { body = String(it.preview.prefix(45)) }
            let mi = NSMenuItem(title: "\(Self.recentsDF.string(from: it.createdAt))   \(icon)\(body)",
                                action: #selector(pasteRecent(_:)), keyEquivalent: "")
            mi.representedObject = it.id
            mi.target = self
            menu.addItem(mi)
        }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = manager.items.first(where: { $0.id == id }) else { return }
        // Nota de voz sin transcripción: no hay texto que copiar → reproducir su audio.
        if item.kind == .text, (item.text?.isEmpty ?? true) {
            if let af = item.audioFileName { AudioPlayer.shared.toggle(fileName: af) }
            return
        }
        manager.copyToPasteboard(item)   // queda en el pasteboard, listo para pegar
    }

    @objc private func showPanel() { panelController.show() }
    @objc private func startVoice() { panelController.toggleVoiceRecording() }
    @objc private func startCapture() { snapController.start() }
    @objc private func startTextCapture() { snapController.startTextCapture() }
    @objc private func startUpload() { panelController.uploadAudio() }
    @objc private func showGuideMenu() { panelController.showGuide() }

    @objc private func openPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController(
                onHotKeyChange: { [weak self] combo in self?.applyHotKey(combo) },
                onVoiceHotKeyChange: { [weak self] combo in self?.applyVoiceHotKey(combo) },
                onCaptureHotKeyChange: { [weak self] combo in self?.applyCaptureHotKey(combo) },
                onUploadHotKeyChange: { [weak self] combo in self?.applyUploadHotKey(combo) },
                onTextCaptureHotKeyChange: { [weak self] combo in self?.applyTextCaptureHotKey(combo) },
                onMaxItemsChange: { [weak self] in self?.manager.applyMaxItems() })
        }
        prefsController?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        switch LoginItem.shared.toggle() {
        case .success:
            launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        case .failure(let err):
            if case .requiresApproval = err { LoginItem.shared.openSystemSettings() }
            let alert = NSAlert()
            alert.messageText = L10n.t("login.title")
            alert.informativeText = err.localizedDescription
            alert.runModal()
            launchItem?.state = LoginItem.shared.isEnabledOrPending ? .on : .off
        }
    }

    @objc private func enableAutoPaste() {
        if Paster.ensureAccessibilityPermission(prompt: true) {
            showAlert(L10n.t("autopaste.enabled.title"), L10n.t("autopaste.enabled.info"))
        } else {
            // Aún sin conceder: el diálogo del sistema se abrió de forma asíncrona. Decirle al usuario qué hacer, en vez
            // de no hacer nada en silencio (el caso común — hizo clic aquí porque no le funcionaba).
            showAlert(L10n.t("autopaste.denied.title"), L10n.t("autopaste.denied.info"))
        }
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("clear.title")
        alert.informativeText = L10n.t("clear.info")
        let del = alert.addButton(withTitle: L10n.t("clear.confirm"))
        del.hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"   // Esc cancela (no se asigna automáticamente en español)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { manager.clearAll() }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func exportBackup() {
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.zip]
        sp.nameFieldStringValue = "Klip-backup.zip"
        sp.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            guard resp == .OK, let url = sp.url, let self else { return }
            self.manager.pauseMonitoring()   // evitar que el sondeo agregue/recorte medios a mitad de copia (corrompería el zip)
            DispatchQueue.global(qos: .userInitiated).async {   // ídem + copia pesada: fuera del hilo principal
                do {
                    try Storage.shared.exportBackup(to: url)
                    DispatchQueue.main.async { self.manager.resumeMonitoring() }
                } catch {
                    DispatchQueue.main.async { self.showAlert(L10n.t("export.fail"), error.localizedDescription); self.manager.resumeMonitoring() }
                }
            }
        }
    }

    @objc private func importBackup() {
        let op = NSOpenPanel()
        op.allowedContentTypes = [.zip]
        op.allowsMultipleSelection = false
        op.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        op.begin { [weak self] resp in
            guard let self, resp == .OK, let url = op.url else { return }
            // No importar mientras una nota de voz aún se transcribe: la importación reemplaza el directorio
            // de audio y los ítems, y la transcripción en vuelo se resolvería contra ids obsoletos.
            guard !self.manager.hasActiveTranscription, !self.panelController.isBusyWithAudio else {
                self.showAlert(L10n.t("import.busy.title"), L10n.t("import.busy.info")); return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.t("import.title")
            alert.informativeText = L10n.t("import.info")
            let ok = alert.addButton(withTitle: L10n.t("import.confirm")); ok.hasDestructiveAction = true
            let cancel = alert.addButton(withTitle: L10n.t("common.cancel")); cancel.keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            self.manager.pauseMonitoring()   // evitar que el sondeo escriba en el store durante la importación
            DispatchQueue.global(qos: .userInitiated).async {   // ídem + copia pesada: fuera del hilo principal
                do {
                    let items = try Storage.shared.importBackup(from: url)
                    DispatchQueue.main.async { self.manager.reload(items); self.manager.resumeMonitoring() }
                } catch {
                    DispatchQueue.main.async { self.showAlert(L10n.t("import.fail"), error.localizedDescription); self.manager.resumeMonitoring() }
                }
            }
        }
    }

    private func showAlert(_ title: String, _ info: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "OK"); a.runModal()
    }
}
