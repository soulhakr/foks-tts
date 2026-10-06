import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

// MARK: - global hotkeys (Carbon; needs no permission)

enum HotKeys {
    static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    static func register(_ keyCode: Int, id: UInt32, _ handler: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKeys.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4F545453), id: id)
        RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | optionKey | controlKey), hkID, GetApplicationEventTarget(), 0, &ref)
        handlers[id] = handler
    }
}

// MARK: - Services menu provider ("Read Aloud with FOKS TTS")

/// Receives the selected text from any app that offers the Services menu. Needs no permission: the sending app
/// hands us the text on the pasteboard.
final class ServiceProvider: NSObject {
    var onText: ((String) -> Void)?

    @objc func readAloud(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "There is no text to read." as NSString
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onText?(text) }
    }
}

// MARK: - app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var overlay: ReaderOverlay?
    var settingsWindow: NSWindow?
    let popover = NSPopover()
    var bag = Set<AnyCancellable>()
    var previewSession: ReadingSession?
    var askedAccessibility = false
    let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"), let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            status.button?.image = img
        } else {
            status.button?.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "FOKS TTS")
        }
        status.button?.toolTip = "FOKS TTS — loading voice…"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: RateView())

        TTSWorker.shared.onReadyChanged = { [weak self] in
            self?.status.button?.toolTip = TTSWorker.shared.isReady ? "FOKS TTS" : "FOKS TTS — loading voice…"
            StatusModel.shared.refresh()
        }
        TTSWorker.shared.start()
        Settings.shared.$rate.sink { [weak self] r in self?.overlay?.session.setRate(r) }.store(in: &bag)

        HotKeys.register(kVK_ANSI_W, id: 1) { [weak self] in self?.read(.window) }
        HotKeys.register(kVK_ANSI_A, id: 2) { [weak self] in self?.read(.area) }
        HotKeys.register(kVK_ANSI_S, id: 3) { [weak self] in self?.read(.screen) }
        HotKeys.register(kVK_ANSI_V, id: 4) { [weak self] in self?.readClipboard() }
        HotKeys.register(kVK_ANSI_T, id: 7) { [weak self] in self?.readSelection() }
        HotKeys.register(kVK_ANSI_P, id: 5) { [weak self] in self?.overlay?.session.pauseResume() }
        HotKeys.register(kVK_ANSI_Period, id: 6) { [weak self] in self?.stopReading() }

        serviceProvider.onText = { [weak self] text in self?.readText(text) }
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        Log.write("---- launch: accessibility=\(AXText.trusted(prompt: false)) screenRecording=\(CGPreflightScreenCaptureAccess()) screens=\(NSScreen.screens.count)")
        runTestMode()
    }

    func applicationWillTerminate(_ n: Notification) { TTSWorker.shared.stop() }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ key: String, _ sel: Selector?, mods: NSEvent.ModifierFlags = [.control, .option, .command]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            menu.addItem(i)
            return i
        }
        _ = item("Read Window…", "w", #selector(menuWindow))
        _ = item("Read Selected Area…", "a", #selector(menuArea))
        _ = item("Read Entire Screen", "s", #selector(menuScreen))
        _ = item("Read Selected Text", "t", #selector(menuSelection))
        _ = item("Read Clipboard Image", "v", #selector(menuClipboard))
        menu.addItem(.separator())
        let reading = overlay != nil
        let pause = item(overlay?.session.isPaused == true ? "Resume" : "Pause", "p", reading ? #selector(menuPause) : nil)
        pause.isEnabled = reading
        let stop = item("Stop Reading", ".", reading ? #selector(menuStop) : nil)
        stop.isEnabled = reading
        menu.addItem(.separator())
        _ = item("Speaking Rate… (\(rateLabel(Settings.shared.rate)))", "", #selector(showRate), mods: [])
        let voiceItem = NSMenuItem(title: "Voice: \(Settings.shared.voiceName(Settings.shared.voice))", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for g in Settings.shared.voiceGroups {
            let h = NSMenuItem(title: g.id, action: nil, keyEquivalent: "")
            h.isEnabled = false
            sub.addItem(h)
            for v in g.voices {
                let vi = NSMenuItem(title: v.name, action: #selector(pickVoice(_:)), keyEquivalent: "")
                vi.target = self
                vi.representedObject = v.id
                vi.state = v.id == Settings.shared.voice ? .on : .off
                sub.addItem(vi)
            }
        }
        voiceItem.submenu = sub
        menu.addItem(voiceItem)
        _ = item("Settings…", ",", #selector(openSettings), mods: [.command])
        menu.addItem(.separator())
        _ = item("Quit FOKS TTS", "q", #selector(NSApplication.terminate(_:)), mods: [.command]).target = NSApp
    }

    @objc func menuWindow() { read(.window) }
    @objc func menuArea() { read(.area) }
    @objc func menuScreen() { read(.screen) }
    @objc func menuClipboard() { readClipboard() }
    @objc func menuSelection() { readSelection() }
    @objc func menuPause() { overlay?.session.pauseResume() }
    @objc func menuStop() { stopReading() }
    @objc func pickVoice(_ i: NSMenuItem) { if let id = i.representedObject as? String { Settings.shared.voice = id } }

    @objc func showRate() {
        guard let b = status.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(onPreview: { [weak self] in self?.previewVoice() },
                                                                                 onInstallAddon: { [weak self] in self?.installAddon() },
                                                                                 onRemoveAddon: { [weak self] in self?.removeAddon() })))
            w.title = "FOKS TTS Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func installAddon() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Install the optional pronunciation add-on?"
        a.informativeText = "This downloads two packages from PyPI: phonemizer-fork (GPL-3.0-or-later) and espeakng-loader, which bundles the eSpeak NG library (GPL-3.0), plus a few small helper libraries. They are separate from FOKS and licensed under the GNU General Public License, not this app's license. Their files are verified against fixed hashes. You can remove them again at any time."
        a.addButton(withTitle: "Install")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        StatusModel.shared.busy = true
        StatusModel.shared.error = nil
        OptionalPackages.install { err in
            StatusModel.shared.busy = false
            StatusModel.shared.error = err
            if err == nil { TTSWorker.shared.restart() }
        }
    }

    func removeAddon() {
        StatusModel.shared.busy = true
        StatusModel.shared.error = nil
        OptionalPackages.uninstall { err in
            StatusModel.shared.busy = false
            StatusModel.shared.error = err
            if err == nil { TTSWorker.shared.restart() }
        }
    }

    func previewVoice() {
        previewSession?.stop()
        let sample = "This is how I sound. I can read text from any window, area, or screen.".split(separator: " ").map {
            Word(text: String($0), x: 0, y: 0, w: 0, h: 0)
        }
        let s = ReadingSession(words: sample)
        previewSession = s
        s.begin()
    }

    // MARK: reading

    func stopReading() {
        overlay?.session.stop()
        overlay?.close()
        overlay = nil
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    func ensureScreenAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        _ = CGRequestScreenCaptureAccess()
        alert("Screen Recording permission needed",
              "To read an area or the whole screen, allow FOKS TTS in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. (Reading a window through Accessibility does not need it.)")
        return false
    }

    func read(_ mode: CaptureMode) {
        stopReading()
        Log.write("read(\(mode))")
        Capture.select(mode) { [weak self] sel in
            guard let self, let sel else { Log.write("selection cancelled"); return }
            Log.write("selected: \(sel)")
            self.process(sel, mode: mode)
        }
    }

    func process(_ sel: Selection, mode: CaptureMode) {
        Task { @MainActor in
            let source = Settings.shared.windowSource
            if case .window(let id, let rect, let pid) = sel, source != "ocr" {
                if !AXText.trusted(prompt: false) {
                    if !askedAccessibility { askedAccessibility = true; _ = AXText.trusted(prompt: true) }
                    if source == "accessibility" { Toast.show("Grant Accessibility access to read windows directly"); return }
                } else {
                    let cg = appKitToCG(rect)
                    let t0 = Date()
                    let words = await Task.detached { AXText.words(pid: pid, windowID: id, rectCG: cg) }.value
                    Log.write("AX result: \(words.map { "\($0.count) words" } ?? "nil") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
                    if let w = words, w.count >= 3 {
                        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main ?? NSScreen.screens[0]
                        start(words: w, rect: rect, screen: screen, image: nil)
                        return
                    }
                    if source == "accessibility" { Toast.show("No accessible text in that window"); return }
                }
            }
            guard ensureScreenAccess() else { return }
            do {
                let r = try await Capture.capture(sel)
                let top = mode == .screen ? Double(max(NSStatusBar.system.thickness, r.screen.safeAreaInsets.top)) / Double(r.rect.height) : 0
                let img = r.image
                let t0 = Date()
                let words = try await Task.detached { try ocrWords(img, ignoreTopFraction: top) }.value
                Log.write("OCR: \(words.count) words in \(Int(Date().timeIntervalSince(t0) * 1000)) ms, image \(img.width)x\(img.height), rect \(r.rect)")
                if words.isEmpty { Toast.show("No text found"); return }
                start(words: words, rect: r.rect, screen: r.screen, image: nil)
            } catch {
                Log.write("capture failed: \(error)")
                alert("Capture failed", "\(error)")
            }
        }
    }

    func readClipboard() {
        stopReading()
        guard let img = (NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show("No image on the clipboard"); return
        }
        Task { @MainActor in
            let words = (try? await Task.detached { try ocrWords(cg) }.value) ?? []
            if words.isEmpty { Toast.show("No text found"); return }
            start(words: words, rect: .zero, screen: NSScreen.main ?? NSScreen.screens[0], image: img)
        }
    }

    /// Read the text selected in the frontmost app via Accessibility (like Speak Selection), highlighting in place
    /// when the app reports where the words are.
    func readSelection() {
        stopReading()
        Log.write("readSelection()")
        guard AXText.trusted(prompt: false) else {
            Toast.show("Grant Accessibility access to read the selection")
            if !askedAccessibility { askedAccessibility = true; _ = AXText.trusted(prompt: true) }
            return
        }
        Task { @MainActor in
            let result = await Task.detached { AXText.selection() }.value
            guard let r = result else {
                Toast.show("No selected text found. Try the Services menu: Read Aloud with FOKS TTS")
                return
            }
            Log.write("selection: \(r.words.count) words, geometry=\(r.rectCG != nil)")
            if let cg = r.rectCG {
                let rect = cgToAppKit(cg)
                let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? screenUnderMouse()
                start(words: r.words, rect: rect, screen: screen, image: nil)
            } else {
                startControlsOnly(words: r.words)
            }
        }
    }

    /// Text handed over by the Services menu (no on-screen geometry, so no highlight; controls only).
    func readText(_ text: String) {
        stopReading()
        let words = text.split(whereSeparator: { $0.isWhitespace }).map { Word(text: String($0), x: 0, y: 0, w: 0, h: 0) }
        Log.write("service: \(words.count) words")
        if words.isEmpty { return }
        startControlsOnly(words: words)
    }

    func startControlsOnly(words: [Word]) {
        Log.write("start reading (controls only): \(words.count) words, voice=\(Settings.shared.voice), rate=\(Settings.shared.rate)")
        let s = ReadingSession(words: words)
        let o = ReaderOverlay(session: s, rect: .zero, screen: screenUnderMouse(), image: nil, controlsOnly: true)
        o.onClose = { [weak self] in self?.overlay = nil }
        s.onError = { [weak self] m in Log.write("reading error: \(m)"); self?.alert("Could not read aloud", m) }
        overlay = o
        o.show()
        s.begin()
    }

    func start(words: [Word], rect: NSRect, screen: NSScreen, image: NSImage?) {
        Log.write("start reading: \(words.count) words, overlay rect \(rect), floating=\(image != nil), voice=\(Settings.shared.voice), rate=\(Settings.shared.rate)")
        let s = ReadingSession(words: words)
        let o = ReaderOverlay(session: s, rect: rect, screen: screen, image: image)
        o.onClose = { [weak self] in self?.overlay = nil }
        s.onError = { [weak self] m in Log.write("reading error: \(m)"); self?.alert("Could not read aloud", m) }
        overlay = o
        o.show()
        s.begin()
    }

    // MARK: headless test mode:  --read-image FILE [--snapshots DIR --at 0.5,2] [--voice ID]

    func runTestMode() {
        var a = Array(CommandLine.arguments.dropFirst())
        var image: String?, dir: String?, times: [Double] = []
        while !a.isEmpty {
            let k = a.removeFirst()
            if k == "--read-image", !a.isEmpty { image = a.removeFirst() }
            else if k == "--snapshots", !a.isEmpty { dir = a.removeFirst() }
            else if k == "--at", !a.isEmpty { times = a.removeFirst().split(separator: ",").compactMap { Double($0) } }
            else if k == "--voice", !a.isEmpty { Settings.shared.voice = a.removeFirst() }
        }
        guard let path = image, let img = NSImage(contentsOfFile: path),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        guard let words = try? ocrWords(cg), !words.isEmpty else { FileHandle.standardError.write(Data("no text\n".utf8)); exit(1) }
        let s = ReadingSession(words: words)
        let o = ReaderOverlay(session: s, rect: .zero, screen: NSScreen.main ?? NSScreen.screens[0], image: img)
        overlay = o
        o.show()
        if let d = dir {
            try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            s.collectOnly = { chunks in
                for (n, t) in times.enumerated() {
                    var base = 0.0, idx: Int?
                    for c in chunks {
                        if t < base + c.dur { idx = ReadingSession.wordIndex(c.spans, at: t - base); break }
                        base += c.dur
                    }
                    o.view.current = idx
                    o.view.status = String(format: "t = %.2fs   word %@", t, idx.map { "\"\(words[$0].text)\"" } ?? "—")
                    if let rep = o.view.bitmapImageRepForCachingDisplay(in: o.view.bounds) {
                        o.view.cacheDisplay(in: o.view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(d)/frame_\(n).png"))
                    }
                }
                exit(0)
            }
        }
        s.begin()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
