import AppKit
import ApplicationServices

// Private but long-stable call used by assistive tools to map an AX window to its CGWindowID.
// Fine for a locally built app; it would not pass App Store review.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Reads on-screen text straight from the target app's accessibility tree (what VoiceOver sees).
/// Needs the Accessibility permission; gives exact word rectangles via AXBoundsForRange.
enum AXText {
    static func trusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXComboBox"]

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    private static func string(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    private static func boundsForRange(_ el: AXUIElement, _ r: NSRange) -> CGRect? {
        var cf = CFRange(location: r.location, length: r.length)
        guard let rv = AXValueCreate(.cfRange, &cf) else { return nil }
        var res: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &res) == .success,
              let v = res else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private static func visibleRange(_ el: AXUIElement) -> NSRange? {
        guard let v = attr(el, "AXVisibleCharacterRange") else { return nil }
        var cf = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &cf), cf.length > 0 else { return nil }
        return NSRange(location: cf.location, length: cf.length)
    }

    private static func window(of app: AXUIElement, id: CGWindowID, rectCG: CGRect) -> AXUIElement? {
        guard let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for w in wins {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(w, &wid) == .success, wid == id { return w }
        }
        return wins.first { w in
            guard let f = frame(w) else { return false }
            return abs(f.minX - rectCG.minX) < 3 && abs(f.minY - rectCG.minY) < 3 && abs(f.width - rectCG.width) < 3
        }
    }

    /// The text currently selected in the focused UI element of the frontmost app (like macOS "Speak Selection").
    /// `rectCG` is the union of the per-word rectangles (global CG coordinates) when the app reports them; the
    /// returned words are then normalized to that rectangle. Without geometry the words have zero boxes.
    static func selection() -> (words: [Word], rectCG: CGRect?)? {
        guard trusted(prompt: false) else { Log.write("AX selection: not trusted"); return nil }
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.6)
        guard let appRef = attr(sys, kAXFocusedApplicationAttribute) else { Log.write("AX selection: no focused app"); return nil }
        let app = appRef as! AXUIElement
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        guard let elRef = attr(app, kAXFocusedUIElementAttribute) else { Log.write("AX selection: no focused element"); return nil }
        let el = elRef as! AXUIElement
        guard let text = string(el, kAXSelectedTextAttribute),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.write("AX selection: focused element has no selected text (role \(string(el, kAXRoleAttribute) ?? "?"))"); return nil
        }
        var base = 0
        if let v = attr(el, kAXSelectedTextRangeAttribute) {
            var cf = CFRange()
            if AXValueGetValue(v as! AXValue, .cfRange, &cf) { base = cf.location }
        }
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: "\\S+")
        var items: [(String, CGRect?)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            items.append((ns.substring(with: m.range), boundsForRange(el, NSRange(location: base + m.range.location, length: m.range.length))))
        }
        guard !items.isEmpty else { return nil }
        let rects = items.compactMap { $0.1 }
        if rects.count == items.count, let first = rects.first {
            let u = rects.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -6, dy: -6)
            let words = items.map { (t, r) -> Word in
                let r = r!
                return Word(text: t, x: Double((r.minX - u.minX) / u.width), y: Double((r.minY - u.minY) / u.height),
                            w: Double(r.width / u.width), h: Double(r.height / u.height))
            }
            return (words, u)
        }
        Log.write("AX selection: \(items.count) words but no per-word geometry; reading without a highlight")
        return (items.map { Word(text: $0.0, x: 0, y: 0, w: 0, h: 0) }, nil)
    }

    /// Words in reading order with window-normalized boxes (origin top-left), or nil if AX is unavailable.
    static func words(pid: pid_t, windowID: CGWindowID, rectCG: CGRect, timeout: TimeInterval = 4) -> [Word]? {
        guard trusted(prompt: false) else { Log.write("AX: not trusted"); return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.6)
        // Chromium/Electron/Firefox only build their accessibility tree when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var win = window(of: app, id: windowID, rectCG: rectCG)
        if win == nil { Thread.sleep(forTimeInterval: 0.4); win = window(of: app, id: windowID, rectCG: rectCG) }
        guard let root = win else { Log.write("AX: no AX window for pid \(pid) windowID \(windowID)"); return nil }

        var deadline = Date().addingTimeInterval(timeout)
        var out: [Word] = []
        var visited = 0

        func norm(_ r: CGRect) -> Word? {
            guard r.intersects(rectCG) else { return nil }
            let c = r.intersection(rectCG)
            return Word(text: "", x: Double((c.minX - rectCG.minX) / rectCG.width), y: Double((c.minY - rectCG.minY) / rectCG.height),
                        w: Double(c.width / rectCG.width), h: Double(c.height / rectCG.height))
        }

        func collect(_ el: AXUIElement, role: String) {
            let raw = string(el, kAXValueAttribute) ?? (role == "AXStaticText" ? string(el, kAXTitleAttribute) : nil)
            guard let text = raw, !text.isEmpty, let f = frame(el), f.intersects(rectCG) else { return }
            let ns = text as NSString
            let range = visibleRange(el) ?? NSRange(location: 0, length: ns.length)
            guard range.location + range.length <= ns.length else { return }
            let re = try! NSRegularExpression(pattern: "\\S+")
            for m in re.matches(in: text, range: range) {
                let wtxt = ns.substring(with: m.range)
                let rect = boundsForRange(el, m.range) ?? {
                    let n = max(1, ns.length)
                    return CGRect(x: f.minX + f.width * CGFloat(m.range.location) / CGFloat(n), y: f.minY,
                                  width: f.width * CGFloat(m.range.length) / CGFloat(n), height: f.height)
                }()
                if let b = norm(rect) { out.append(Word(text: wtxt, x: b.x, y: b.y, w: b.w, h: b.h)) }
            }
        }

        func walk(_ el: AXUIElement, depth: Int) {
            if depth > 60 || visited > 8000 || Date() > deadline { return }
            visited += 1
            let role = string(el, kAXRoleAttribute) ?? ""
            if textRoles.contains(role) {
                collect(el, role: role)
                return
            }
            for c in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, depth: depth + 1) }
        }
        walk(root, depth: 0)
        // Chromium/Electron build their accessibility tree a moment after being asked, so a first walk of a
        // web-based window often finds only a handful of elements. If it looks like that, wait and walk again.
        for delay in [0.7, 1.5] where out.count < 3 && visited < 40 {
            Log.write("AX: only \(visited) elements / \(out.count) words; retrying after \(delay)s")
            Thread.sleep(forTimeInterval: delay)
            out = []; visited = 0
            deadline = Date().addingTimeInterval(timeout)
            walk(root, depth: 0)
        }
        Log.write("AX: visited \(visited) elements, \(out.count) words")
        return out
    }
}
