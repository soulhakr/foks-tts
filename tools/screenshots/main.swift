// Renders the README images from the real SwiftUI views, so they never contain a screen capture:
//   settings-light.png, settings-dark.png   the Settings window (fixed demo values, whole dialog)
//   menubar-icon.png                        the menu bar icon on a light and a dark menu bar
// Built and run by tools/render_screenshots.sh (which also sets up the demo home so no real path appears).
// usage: render <output-dir> <path to app/Icon/MenuBarIcon@2x.png>
import AppKit
import SwiftUI

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write(Data("usage: render <out-dir> <MenuBarIcon@2x.png>\n".utf8)); exit(2) }
let outDir = URL(fileURLWithPath: args[1])
let iconURL = URL(fileURLWithPath: args[2])
// the version shown in About comes from app/Info.plist (this harness runs without an app bundle)
let infoURL = iconURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
if let info = NSDictionary(contentsOf: infoURL), let v = info["CFBundleShortVersionString"] as? String {
    AppInfo.override = (info["CFBundleVersion"] as? String).map { "\(v) (build \($0))" } ?? v
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func writePNG(_ rep: NSBitmapImageRep, _ name: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name): \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

/// Drop the empty window background below the last row of content, keeping a small margin.
func cropBottom(_ rep: NSBitmapImageRep, marginPx: Int = 24) -> NSBitmapImageRep {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    func differs(_ y: Int) -> Bool {
        let ref = rep.colorAt(x: 0, y: h - 1)!
        for x in stride(from: 0, to: w, by: 2) {
            let c = rep.colorAt(x: x, y: y)!
            if abs(c.redComponent - ref.redComponent) + abs(c.greenComponent - ref.greenComponent) + abs(c.blueComponent - ref.blueComponent) > 0.02 { return true }
        }
        return false
    }
    var last = h - 1
    while last > 0, !differs(last) { last -= 1 }
    let newH = min(h, last + 1 + marginPx)
    let cg = rep.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: w, height: newH))!
    return NSBitmapImageRep(cgImage: cg)
}

func renderSettings(dark: Bool) -> NSBitmapImageRep {
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let status = StatusModel.shared
    status.frozen = true
    status.ready = true; status.axOK = true; status.scOK = true; status.espeak = true
    let root = SettingsView(onPreview: {}, onInstallAddon: {}, onRemoveAddon: {}, height: 1700)
        .environment(\.controlActiveState, .key)
    let vc = NSHostingController(rootView: root)
    let window = NSWindow(contentViewController: vc)
    window.setContentSize(NSSize(width: 520, height: 1700))
    window.appearance = app.appearance
    window.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))     // let SwiftUI lay out and the controls settle
    let view = vc.view
    view.frame = NSRect(x: 0, y: 0, width: 520, height: 1700)
    view.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1040, pixelsHigh: 3400, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size                                      // 2x: the PNG is 1040 px wide
    view.cacheDisplay(in: view.bounds, to: rep)
    return cropBottom(rep)
}

func renderMenuBar() -> NSBitmapImageRep {
    let w = 360, h = 120, strip = 60
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let icon = NSImage(contentsOf: iconURL)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for (i, dark) in [false, true].enumerated() {
        let y = CGFloat(h - (i + 1) * strip)                         // light strip on top, dark below
        let bg = dark ? NSColor(red: 0.15, green: 0.15, blue: 0.165, alpha: 1) : NSColor(red: 0.92, green: 0.915, blue: 0.94, alpha: 1)
        let pill = dark ? NSColor(white: 0.36, alpha: 1) : NSColor(white: 0.79, alpha: 1)
        bg.setFill(); NSRect(x: 0, y: y, width: CGFloat(w), height: CGFloat(strip)).fill()
        pill.setFill()
        for x in [40, 96, 150, 214] {
            let wd: CGFloat = x == 214 ? 35 : 35
            NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: y + 21, width: wd, height: 18), xRadius: 9, yRadius: 9).fill()
        }
        let r = NSRect(x: 284, y: y + 12, width: 36, height: 36)
        if dark {                                                    // a template image takes the menu bar's text color
            let tinted = NSImage(size: r.size)
            tinted.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: r.size))
            NSColor.white.set()
            NSRect(origin: .zero, size: r.size).fill(using: .sourceIn)
            tinted.unlockFocus()
            tinted.draw(in: r)
        } else {
            icon.draw(in: r)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

writePNG(renderSettings(dark: false), "settings-light.png")
writePNG(renderSettings(dark: true), "settings-dark.png")
writePNG(renderMenuBar(), "menubar-icon.png")
