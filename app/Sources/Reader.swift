import AppKit
import SwiftUI
import AVFoundation

typealias SpanT = (i: Int, start: Double, end: Double)

/// Streams Kokoro audio chunks from the worker, plays them in order, and reports the word being spoken.
final class ReadingSession: NSObject, AVAudioPlayerDelegate, ObservableObject {
    struct Chunk { let url: URL; let spans: [SpanT]; let dur: Double }

    let words: [Word]
    private(set) var chunks: [Chunk] = []
    private var index = 0
    private var player: AVAudioPlayer?
    private var finalReceived = false
    private var waiting = true
    private(set) var stopped = false
    private var jobID: Int?
    private var timer: Timer?
    private let outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foks-tts/\(UUID().uuidString)")

    @Published var isPaused = false
    @Published var statusText = "Preparing…"
    var onWord: ((Int?) -> Void)?
    var onEnd: (() -> Void)?
    var onError: ((String) -> Void)?
    /// Test mode: instead of playing, hand over all chunks once synthesis is complete.
    var collectOnly: (([Chunk]) -> Void)?

    init(words: [Word]) { self.words = words }

    func begin() {
        jobID = TTSWorker.shared.speak(words: words.map { $0.text }, voice: Settings.shared.voice, outDir: outDir) { [weak self] msg in
            self?.handle(msg)
        }
    }

    private func handle(_ msg: [String: Any]) {
        if stopped { return }
        if let err = msg["error"] as? String { onError?(err); stop(); return }
        if let wav = msg["wav"] as? String {
            let spans: [SpanT] = ((msg["spans"] as? [[String: Any]]) ?? []).compactMap { d in
                guard let i = d["i"] as? Int, let s = (d["start"] as? NSNumber)?.doubleValue,
                      let e = (d["end"] as? NSNumber)?.doubleValue else { return nil }
                return (i, s, e)
            }
            chunks.append(Chunk(url: URL(fileURLWithPath: wav), spans: spans, dur: (msg["dur"] as? NSNumber)?.doubleValue ?? 0))
            if collectOnly == nil, waiting { playNext() }
        }
        if msg["final"] != nil {
            finalReceived = true
            if let c = collectOnly { c(chunks) } else if waiting { playNext() }
        }
    }

    private func playNext() {
        if stopped { return }
        guard index < chunks.count else {
            if finalReceived { finish() } else { waiting = true; statusText = "Preparing…" }
            return
        }
        waiting = false
        do {
            let p = try AVAudioPlayer(contentsOf: chunks[index].url)
            p.enableRate = true
            p.rate = Float(Settings.shared.rate)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
        } catch { onError?("Could not play audio: \(error)"); stop(); return }
        statusText = "Reading…"
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        index += 1
        playNext()
    }

    static func wordIndex(_ spans: [SpanT], at t: Double) -> Int? {
        var found: SpanT?
        for s in spans where s.start <= t { found = s }
        guard let f = found, t <= f.end + 0.5 else { return nil }
        return f.i
    }

    private func tick() {
        guard let p = player, p.isPlaying, index < chunks.count else { return }
        onWord?(ReadingSession.wordIndex(chunks[index].spans, at: p.currentTime))
    }

    func pauseResume() {
        guard let p = player else { return }
        if p.isPlaying { p.pause(); isPaused = true; statusText = "Paused" }
        else { p.rate = Float(Settings.shared.rate); p.play(); isPaused = false; statusText = "Reading…" }
    }

    func setRate(_ r: Double) { player?.rate = Float(r) }

    private func finish() {
        statusText = "Done"
        onWord?(nil)
        teardown()
        onEnd?()
    }

    func stop() {
        if stopped { return }
        stopped = true
        if let id = jobID { TTSWorker.shared.cancel(id) }
        player?.stop()
        onWord?(nil)
        teardown()
        onEnd?()
    }

    private func teardown() {
        timer?.invalidate(); timer = nil
        try? FileManager.default.removeItem(at: outDir)
    }
}

// MARK: - highlight view

final class HighlightView: NSView {
    var image: NSImage?
    var words: [Word] = []
    var color: NSColor = .systemYellow
    var current: Int? { didSet { needsDisplay = true } }
    var status = "" { didSet { needsDisplay = true } }
    private let barHeight: CGFloat = 26

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { image != nil }

    func contentRect() -> NSRect {
        guard let img = image else { return bounds }
        let area = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barHeight)
        let s = min(area.width / img.size.width, area.height / img.size.height)
        let w = img.size.width * s, h = img.size.height * s
        return NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = contentRect()
        if let img = image {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            (status as NSString).draw(at: NSPoint(x: 10, y: bounds.height - barHeight + 6), withAttributes: attrs)
        }
        guard let c = current, c < words.count else { return }
        let w = words[c]
        let hr = NSRect(x: r.minX + w.x * r.width - 3, y: r.minY + w.y * r.height - 2, width: w.w * r.width + 6, height: w.h * r.height + 4)
        let path = NSBezierPath(roundedRect: hr, xRadius: 4, yRadius: 4)
        color.withAlphaComponent(0.45).setFill()
        path.fill()
        color.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { window?.close() }
    }
}

// MARK: - overlay (in place over the source, or a floating window showing the captured image)

final class ReaderOverlay: NSObject, NSWindowDelegate {
    let session: ReadingSession
    let view = HighlightView()
    private(set) var window: NSWindow
    private var pill: NSPanel?
    var onClose: (() -> Void)?
    private let controlsOnly: Bool

    /// `rect` is where to put the overlay (AppKit coordinates). With `image`, a floating viewer is shown instead.
    /// `controlsOnly` shows just the floating transport controls (used for text that has no on-screen geometry).
    init(session: ReadingSession, rect: NSRect, screen: NSScreen, image: NSImage?, controlsOnly: Bool = false) {
        self.session = session
        self.controlsOnly = controlsOnly
        view.words = session.words
        view.color = Settings.shared.highlightColor
        view.image = image
        if let img = image {
            let vis = screen.visibleFrame
            let scale = min(1.0, min(vis.width * 0.7 / img.size.width, vis.height * 0.7 / img.size.height))
            let size = NSSize(width: max(440, img.size.width * scale), height: img.size.height * scale + 26)
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
            window.title = "Reading aloud"
            window.center()
            window.level = .floating
        } else {
            window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        }
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = view
        session.onWord = { [weak self] i in self?.view.current = i }
        session.onEnd = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.close() }
        }
    }

    func show() {
        if controlsOnly { showPill(); return }
        if view.image != nil {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        } else {
            window.orderFrontRegardless()
        }
        if Settings.shared.showControls { showPill() }
    }

    private func showPill() {
        let host = NSHostingView(rootView: PillView(session: session, onStop: { [weak self] in self?.session.stop() }))
        let size = NSSize(width: 340, height: 46)
        host.frame = NSRect(origin: .zero, size: size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating + 1
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        let screen = controlsOnly ? screenUnderMouse() : (window.screen ?? NSScreen.main ?? NSScreen.screens[0])
        let vis = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2, y: vis.maxY - size.height - 14))
        p.orderFrontRegardless()
        pill = p
    }

    func close() {
        pill?.orderOut(nil); pill = nil
        window.delegate = nil
        window.orderOut(nil)
        onClose?()
    }

    func windowWillClose(_ notification: Notification) {
        session.stop()
        pill?.orderOut(nil); pill = nil
    }
}
