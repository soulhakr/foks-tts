import AppKit
import ScreenCaptureKit

enum CaptureMode { case area, window, screen }

/// What the user picked. Rects are AppKit global coordinates (origin bottom-left of the primary screen).
enum Selection {
    case rect(NSRect, NSScreen)
    case window(CGWindowID, NSRect, pid_t)
}

struct CaptureResult {
    let image: CGImage
    let rect: NSRect          // where the image sits on screen (AppKit coordinates)
    let screen: NSScreen
}

enum CaptureError: Error { case noDisplay, noWindow, noAccess }

func primaryHeight() -> CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
func cgToAppKit(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryHeight() - r.maxY, width: r.width, height: r.height) }
func appKitToCG(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight() - r.maxY, width: r.width, height: r.height) }
func displayID(_ s: NSScreen) -> CGDirectDisplayID {
    (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}
func screenUnderMouse() -> NSScreen {
    let p = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
}

// MARK: - on-screen window list

struct WinInfo { let id: CGWindowID; let pid: pid_t; let rect: NSRect; let title: String; let owner: String }

func visibleWindows() -> [WinInfo] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    let me = getpid()
    var out: [WinInfo] = []
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != me,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if r.width < 60 || r.height < 40 { continue }
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let name = w[kCGWindowName as String] as? String ?? ""
        out.append(WinInfo(id: id, pid: pid, rect: cgToAppKit(r), title: name.isEmpty ? owner : "\(owner) — \(name)", owner: owner))
    }
    return out    // front to back
}

// MARK: - selection UI

final class SelectWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectView: NSView {
    let mode: CaptureMode
    let screen: NSScreen
    var windows: [WinInfo] = []
    var hover: WinInfo?
    var start: NSPoint?
    var current: NSPoint?
    var onDone: ((Selection?) -> Void)?

    init(mode: CaptureMode, screen: NSScreen) {
        self.mode = mode
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        if mode == .window { windows = visibleWindows(); Log.write("select: window picker on \(screen.localizedName), \(windows.count) candidate windows") }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: mode == .area ? .crosshair : .pointingHand) }

    func toGlobal(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x + screen.frame.minX, y: p.y + screen.frame.minY) }
    func toLocal(_ r: NSRect) -> NSRect { r.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }

    var dragRect: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    func windowUnderPointer() -> WinInfo? {
        let g = NSEvent.mouseLocation
        if let hit = windows.first(where: { NSMouseInRect(g, $0.rect, false) }) { return hit }
        // Fallback: ask the window server which windows are under the pointer, below our overlay, front to back.
        guard let mine = window else { return nil }
        var below = mine.windowNumber
        for _ in 0..<40 {
            let n = NSWindow.windowNumber(at: g, belowWindowWithWindowNumber: below)
            if n <= 0 { return nil }
            if let w = windows.first(where: { $0.id == CGWindowID(n) }) { return w }
            below = n
        }
        return nil
    }
    override func mouseMoved(with e: NSEvent) {
        guard mode == .window else { return }
        let h = windowUnderPointer()
        if h?.id != hover?.id { hover = h; needsDisplay = true }
    }
    override func mouseDown(with e: NSEvent) {
        Log.write("select: mouseDown mode=\(mode) hover=\(hover.map { "\($0.id)" } ?? "nil")")
        if mode == .area { start = convert(e.locationInWindow, from: nil); current = start; needsDisplay = true }
    }
    override func mouseDragged(with e: NSEvent) {
        if mode == .area { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
    }
    override func mouseUp(with e: NSEvent) {
        Log.write("select: mouseUp mode=\(mode)")
        if mode == .area {
            guard let r = dragRect, r.width > 12, r.height > 12 else { start = nil; current = nil; needsDisplay = true; return }
            onDone?(.rect(r.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), screen))
        } else if mode == .window {
            let h = windowUnderPointer() ?? hover       // hit-test at click time; do not rely on cached hover state
            Log.write("select: mouseUp window=\(h.map { "\($0.id) pid \($0.pid) \($0.owner)" } ?? "none under pointer"); pointer \(NSEvent.mouseLocation), view screen \(screen.localizedName) \(screen.frame)")
            if h == nil { for w in windows { Log.write("  candidate \(w.id) \(w.owner) \(w.rect)") } }
            if let h { onDone?(.window(h.id, h.rect, h.pid)) }
        }
    }
    override func rightMouseDown(with e: NSEvent) { onDone?(nil) }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        let hole: NSRect? = mode == .area ? dragRect : hover.map { toLocal($0.rect) }
        if let r = hole {
            // Not fully transparent: macOS lets mouse clicks pass straight through pixels with alpha 0, so a clear
            // hole would send the click on the highlighted window to the app underneath instead of to this picker.
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.saveGState()
                cg.setBlendMode(.copy)
                cg.setFillColor(CGColor(gray: 0, alpha: 0.02))
                cg.fill(r)
                cg.restoreGState()
            }
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: r)
            p.lineWidth = 2
            p.stroke()
            var label = "\(Int(r.width)) × \(Int(r.height))"
            if mode == .window, let h = hover { label = h.title }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                        .foregroundColor: NSColor.white,
                                                        .backgroundColor: NSColor.black.withAlphaComponent(0.7)]
            (" \(label) " as NSString).draw(at: NSPoint(x: r.minX + 4, y: max(2, r.minY - 20)), withAttributes: attrs)
        } else {
            let hint = mode == .area ? "Drag to select the area to read — Esc to cancel"
                                     : "Click a window to read it — Esc to cancel"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium),
                                                        .foregroundColor: NSColor.white]
            let sz = (hint as NSString).size(withAttributes: attrs)
            (hint as NSString).draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY), withAttributes: attrs)
        }
    }
}

enum Capture {
    private static var selectWindows: [SelectWindow] = []

    /// Show the picker overlay (area / window). `.screen` needs no UI: it is the screen under the mouse.
    static func select(_ mode: CaptureMode, completion: @escaping (Selection?) -> Void) {
        if mode == .screen {
            let s = screenUnderMouse()
            completion(.rect(s.frame, s))
            return
        }
        var finished = false
        let finish: (Selection?) -> Void = { sel in
            if finished { return }
            finished = true
            selectWindows.forEach { $0.orderOut(nil) }
            selectWindows = []
            NSCursor.arrow.set()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { completion(sel) }
        }
        selectWindows = NSScreen.screens.map { screen in
            let w = SelectWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = SelectView(mode: mode, screen: screen)
            v.onDone = finish
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            return w
        }
        NSApp.activate(ignoringOtherApps: true)
        for w in selectWindows { w.makeKeyAndOrderFront(nil) }
        if let first = selectWindows.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? selectWindows.first {
            first.makeKey()
            first.makeFirstResponder(first.contentView)
        }
    }

    /// Capture the selection with ScreenCaptureKit (our own windows are excluded).
    static func capture(_ sel: Selection) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let cfg = SCStreamConfiguration()
        cfg.showsCursor = false
        switch sel {
        case .window(let id, let rect, _):
            guard let w = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.noWindow }
            let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main ?? NSScreen.screens[0]
            let scale = screen.backingScaleFactor
            cfg.width = Int(w.frame.width * scale)
            cfg.height = Int(w.frame.height * scale)
            let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w),
                                                                 configuration: cfg)
            return CaptureResult(image: img, rect: cgToAppKit(w.frame), screen: screen)
        case .rect(let rect, let screen):
            guard let d = content.displays.first(where: { $0.displayID == displayID(screen) }) else { throw CaptureError.noDisplay }
            let me = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: d, excludingApplications: me, exceptingWindows: [])
            let cg = appKitToCG(rect)
            cfg.sourceRect = CGRect(x: cg.minX - d.frame.minX, y: cg.minY - d.frame.minY, width: cg.width, height: cg.height)
            cfg.width = Int(rect.width * screen.backingScaleFactor)
            cfg.height = Int(rect.height * screen.backingScaleFactor)
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            return CaptureResult(image: img, rect: rect, screen: screen)
        }
    }
}
