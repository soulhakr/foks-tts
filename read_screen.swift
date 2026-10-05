// Read an image (clipboard by default) aloud with a highlight that follows the spoken word.
// OCR: Apple Vision (word boxes). Speech + word timing: speak_words.py (Kokoro, offline).
// Run uncompiled:  swift read_screen.swift [--image file.png] [--snapshots DIR --at 0.5,2,4]
// Window: Esc quits, Space pauses/resumes.
import AppKit
import Vision
import AVFoundation

struct Word: Codable {
    let text: String
    let x: Double
    let y: Double      // normalized, origin top-left
    let w: Double
    let h: Double
    let line: Int
}
struct Payload: Codable { let words: [Word] }
struct Span: Codable {
    let i: Int
    let start: Double
    let end: Double
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - arguments
var imagePath: String? = nil
var snapshotDir: String? = nil
var snapshotTimes: [Double] = []
do {
    var a = Array(CommandLine.arguments.dropFirst())
    while !a.isEmpty {
        let k = a.removeFirst()
        if k == "--image", !a.isEmpty { imagePath = a.removeFirst() }
        else if k == "--snapshots", !a.isEmpty { snapshotDir = a.removeFirst() }
        else if k == "--at", !a.isEmpty { snapshotTimes = a.removeFirst().split(separator: ",").compactMap { Double($0) } }
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - image + OCR
func loadImage() -> NSImage? {
    if let p = imagePath { return NSImage(contentsOfFile: p) }
    let objs = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)
    return (objs as? [NSImage])?.first
}

func ocrWords(_ cg: CGImage) throws -> [Word] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: cg).perform([req])
    let obs: [VNRecognizedTextObservation] = req.results ?? []
    let byTop = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var rows: [[VNRecognizedTextObservation]] = []
    for o in byTop {
        if let ref = rows.last?.first {
            let tol = 0.5 * min(ref.boundingBox.height, o.boundingBox.height)
            if abs(ref.boundingBox.midY - o.boundingBox.midY) < tol {
                rows[rows.count - 1].append(o)
                continue
            }
        }
        rows.append([o])
    }
    var words: [Word] = []
    var line = 0
    for row in rows {
        for o in row.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
            guard let cand = o.topCandidates(1).first else { continue }
            let s = cand.string
            var i = s.startIndex
            while i < s.endIndex {
                while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
                if i >= s.endIndex { break }
                var j = i
                while j < s.endIndex, !s[j].isWhitespace { j = s.index(after: j) }
                let r = i..<j
                let rect: CGRect = (try? cand.boundingBox(for: r))?.boundingBox ?? o.boundingBox
                words.append(Word(text: String(s[r]), x: Double(rect.minX), y: Double(1 - rect.maxY),
                                  w: Double(rect.width), h: Double(rect.height), line: line))
                i = j
            }
            line += 1
        }
    }
    return words
}

// MARK: - view
final class ReaderView: NSView {
    let image: NSImage
    var words: [Word] = []
    var current: Int? = nil { didSet { needsDisplay = true } }
    var status = "Reading text..." { didSet { needsDisplay = true } }
    let barHeight: CGFloat = 28

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func fitRect() -> NSRect {
        let area = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barHeight)
        let s = min(area.width / image.size.width, area.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        return NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let r = fitRect()
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let c = current, c < words.count {
            let w = words[c]
            let hr = NSRect(x: r.minX + w.x * r.width - 3, y: r.minY + w.y * r.height - 2,
                            width: w.w * r.width + 6, height: w.h * r.height + 4)
            let path = NSBezierPath(roundedRect: hr, xRadius: 4, yRadius: 4)
            NSColor.systemYellow.withAlphaComponent(0.5).setFill()
            path.fill()
            NSColor.systemOrange.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        (status as NSString).draw(at: NSPoint(x: 10, y: bounds.height - barHeight + 7), withAttributes: attrs)
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { NSApp.terminate(nil) }          // Esc
        else if e.keyCode == 49 { togglePause() }            // Space
    }
}

// MARK: - run
guard let image = loadImage() else { fail("No image on the clipboard (or --image not readable).") }
guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("Could not decode image.") }
let words: [Word]
do { words = try ocrWords(cg) } catch { fail("OCR failed: \(error)") }
if words.isEmpty { fail("No text found in the image.") }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
let scale = min(1.0, min(screen.width * 0.7 / image.size.width, screen.height * 0.7 / image.size.height))
let content = NSRect(x: 0, y: 0, width: max(420, image.size.width * scale), height: image.size.height * scale + 28)
let view = ReaderView(image: image, frame: content)
view.words = words
let window = NSWindow(contentRect: content, styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Reading aloud (Esc to stop, Space to pause)"
window.level = .floating
window.contentView = view
window.center()
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
app.activate(ignoringOtherApps: true)

var player: AVAudioPlayer? = nil
var spans: [Span] = []
var timer: Timer? = nil

func togglePause() {
    guard let p = player else { return }
    if p.isPlaying { p.pause(); view.status = "Paused" } else { p.play(); view.status = "Reading..." }
}

func spanIndex(at t: Double) -> Int? {
    var found: Int? = nil
    for s in spans where s.start <= t { found = s.i }
    if let f = found, let last = spans.last, t > last.end + 0.4, f == last.i { return nil }
    return found
}

func writeSnapshot(_ path: String) {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

func startPlayback(wav: URL) {
    if let dir = snapshotDir {                       // test mode: render frames, no audio
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (n, t) in snapshotTimes.enumerated() {
            view.current = spanIndex(at: t)
            view.status = String(format: "t = %.2fs", t)
            writeSnapshot("\(dir)/frame_\(n).png")
        }
        exit(0)
    }
    guard let p = try? AVAudioPlayer(contentsOf: wav) else { fail("Could not play audio.") }
    player = p
    p.prepareToPlay()
    view.status = "Reading..."
    p.play()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
        guard let p = player else { return }
        if p.isPlaying { view.current = spanIndex(at: p.currentTime) }
        else if p.currentTime == 0 || p.currentTime >= p.duration - 0.05 {
            view.current = nil
            view.status = "Done"
            timer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSApp.terminate(nil) }
        }
    }
}

// OCR words -> speech + timeline (background), then play (main)
DispatchQueue.global().async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("offline-tts-\(getpid())")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let wordsJSON = tmp.appendingPathComponent("words.json")
    let wav = tmp.appendingPathComponent("reading.wav")
    let timeline = tmp.appendingPathComponent("timeline.json")
    do { try JSONEncoder().encode(Payload(words: words)).write(to: wordsJSON) } catch { fail("\(error)") }

    let p = Process()
    p.executableURL = home.appendingPathComponent("AI/mlx-env/bin/python")
    p.arguments = [here.appendingPathComponent("speak_words.py").path, wordsJSON.path, wav.path, timeline.path]
    var env = ProcessInfo.processInfo.environment
    env["HF_HUB_OFFLINE"] = "1"
    p.environment = env
    let err = Pipe()
    p.standardError = err
    do { try p.run() } catch { fail("Could not start TTS: \(error)") }
    let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("TTS failed:\n\(errText)") }
    if let d = try? Data(contentsOf: timeline), let s = try? JSONDecoder().decode([Span].self, from: d) {
        spans = s.sorted { $0.start < $1.start }
    }
    DispatchQueue.main.async { startPlayback(wav: wav) }
}

app.run()
