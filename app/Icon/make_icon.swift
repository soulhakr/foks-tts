// Generates the app icon (AppIcon.icns) and menubar template procedurally. No external assets.
//   swift make_icon.swift                  -> writes AppIcon.icns + MenuBarIcon*.png for the chosen STYLE
//   swift make_icon.swift --concepts DIR   -> writes one PNG per palette and a contact sheet
import AppKit


func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ink = rgb(27, 31, 59), cream = rgb(255, 247, 238), vermilion = rgb(232, 69, 14)
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// ---- fox head geometry, local coordinates (y up, centre 0,0). Built as a left half, then mirrored.
func sym(_ left: CGPath) -> CGPath {
    let p = CGMutablePath()
    p.addPath(left)
    p.addPath(left, transform: CGAffineTransform(scaleX: -1, y: 1))
    return p
}
func headLeft() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(0, 215))
    p.addCurve(to: P(-262, 80), control1: P(-90, 215), control2: P(-200, 175))
    p.addCurve(to: P(-215, -75), control1: P(-290, 30), control2: P(-270, -30))
    p.addCurve(to: P(-28, -215), control1: P(-150, -135), control2: P(-70, -195))
    p.addLine(to: P(0, -218))
    p.closeSubpath()
    return p
}
func earLeft() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(-258, 95))
    p.addCurve(to: P(-200, 392), control1: P(-262, 210), control2: P(-240, 320))
    p.addCurve(to: P(-35, 205), control1: P(-135, 345), control2: P(-70, 285))
    p.closeSubpath()
    return p
}
func earInnerLeft() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(-226, 150))
    p.addCurve(to: P(-198, 348), control1: P(-228, 230), control2: P(-218, 305))
    p.addCurve(to: P(-84, 215), control1: P(-156, 318), control2: P(-112, 268))
    p.closeSubpath()
    return p
}
func earTipLeft() -> CGPath {          // dark tip (top ~25% of the ear)
    let p = CGMutablePath()
    p.move(to: P(-200, 392))
    p.addCurve(to: P(-240, 312), control1: P(-220, 372), control2: P(-234, 345))
    p.addCurve(to: P(-150, 330), control1: P(-205, 318), control2: P(-175, 325))
    p.addCurve(to: P(-200, 392), control1: P(-170, 350), control2: P(-185, 372))
    p.closeSubpath()
    return p
}
func muzzleLeft() -> CGPath {           // white cheek + muzzle area, clipped to the head
    let p = CGMutablePath()
    p.move(to: P(-310, 45))
    p.addCurve(to: P(-62, -16), control1: P(-215, -8), control2: P(-130, -22))
    p.addCurve(to: P(0, -42), control1: P(-32, -14), control2: P(-14, -42))
    p.addLine(to: P(0, -320)); p.addLine(to: P(-310, -320)); p.closeSubpath()
    return p
}

/// Gradient-fill the UNION of several shapes (each clipped separately: combining outlines of opposite
/// winding into one path would cancel their overlap into a hole).
func gradient(_ ctx: CGContext, _ paths: [CGPath], _ top: CGColor, _ bottom: CGColor, _ y0: CGFloat, _ y1: CGFloat) {
    let g = CGGradient(colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: [0, 1])!
    for path in paths {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(g, start: P(0, y0), end: P(0, y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
}
func fillPath(_ ctx: CGContext, _ p: CGPath, _ c: CGColor) { ctx.addPath(p); ctx.setFillColor(c); ctx.fillPath() }
func ellipse(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}

// ---- palettes: colours come from brand/palette.json (single source of truth; see brand/BRAND.md).
// The identity is a deep rust/copper fox (not Firefox's yellow-orange) on forest green or sand, never blue or violet.
let brand: [String: [String: String]] = {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try! Data(contentsOf: root.appendingPathComponent("brand/palette.json"))
    return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["tokens"] as! [String: [String: String]]
}()
func tok(_ family: String, _ step: String) -> CGColor {
    let h = brand[family]![step]!.dropFirst()
    let v = Int(h, radix: 16)!
    return rgb((v >> 16) & 255, (v >> 8) & 255, v & 255)
}
struct Palette {
    let name: String
    let bgTop, bgBottom, headTop, headBottom, muzzle, earInner, earTip, dark, bubble, bars: CGColor
}
let white = tok("sand", "50")        // "white" in this icon is the warm sand-50
let palettes: [Palette] = [
    Palette(name: "rust-forest", bgTop: tok("forest", "600"), bgBottom: tok("forest", "900"), headTop: tok("rust", "500"), headBottom: tok("rust", "600"),
            muzzle: tok("sand", "100"), earInner: tok("rust", "800"), earTip: tok("rust", "900"), dark: tok("rust", "900"),
            bubble: tok("sand", "50"), bars: tok("rust", "600")),
    Palette(name: "rust-sand", bgTop: tok("sand", "50"), bgBottom: tok("sand", "300"), headTop: tok("rust", "500"), headBottom: tok("rust", "600"),
            muzzle: tok("sand", "50"), earInner: tok("rust", "800"), earTip: tok("rust", "900"), dark: tok("rust", "900"),
            bubble: tok("sand", "800"), bars: tok("sand", "100")),
]
let chosenPalette = 0

// ---- friendly fox
func foxFriendly(_ ctx: CGContext, _ pal: Palette) {
    gradient(ctx, [sym(headLeft()), sym(earLeft())], pal.headTop, pal.headBottom, 400, -220)
    fillPath(ctx, sym(earInnerLeft()), pal.earInner)
    fillPath(ctx, sym(earTipLeft()), pal.earTip)
    ctx.saveGState(); ctx.addPath(sym(headLeft())); ctx.clip()
    fillPath(ctx, sym(muzzleLeft()), pal.muzzle)
    ctx.restoreGState()
    for sx: CGFloat in [-1, 1] {
        ellipse(ctx, 100 * sx, 58, 40, 56, pal.dark)
        ellipse(ctx, 90 * sx, 76, 15, 15, white)
    }
    ellipse(ctx, 0, -196, 62, 42, pal.dark)
}

func bubble(_ ctx: CGContext, _ pal: Palette) {
    let c = P(724, 706), rx: CGFloat = 140, ry: CGFloat = 100
    let tail = CGMutablePath()
    tail.move(to: P(668, 644))
    tail.addCurve(to: P(592, 556), control1: P(660, 604), control2: P(628, 574))
    tail.addCurve(to: P(722, 624), control1: P(640, 566), control2: P(700, 590))
    tail.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: rgb(0, 0, 0, 0.32))
    ctx.setFillColor(pal.bubble)
    ctx.fillEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    fillPath(ctx, tail, pal.bubble)
    ctx.restoreGState()
    ctx.setStrokeColor(pal.bars); ctx.setLineCap(.round); ctx.setLineWidth(22)
    for (i, h) in ([34, 70, 104, 70, 38] as [CGFloat]).enumerated() {
        let x = c.x - 88 + CGFloat(i) * 44
        ctx.beginPath(); ctx.move(to: P(x, c.y - h / 2)); ctx.addLine(to: P(x, c.y + h / 2)); ctx.strokePath()
    }
}

func drawIcon(_ ctx: CGContext, _ pal: Palette) {
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 188, cornerHeight: 188, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.38))
    fillPath(ctx, squircle, pal.bgBottom)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let g = CGGradient(colorsSpace: sRGB, colors: [pal.bgTop, pal.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: P(512, 924), end: P(512, 100), options: [])
    let hl = CGGradient(colorsSpace: sRGB, colors: [rgb(255, 255, 255, 0.14), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: P(512, 924), end: P(512, 640), options: [])
    ctx.saveGState()
    ctx.translateBy(x: 368, y: 440)
    ctx.scaleBy(x: 0.86, y: 0.86)
    foxFriendly(ctx, pal)
    ctx.restoreGState()
    bubble(ctx, pal)
    ctx.restoreGState()
}

func render(_ px: Int, _ body: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    body(ctx)
    return ctx.makeImage()!
}
func writePNG(_ img: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func icon(_ px: Int, _ pal: Palette) -> CGImage {
    render(px) { ctx in ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024); drawIcon(ctx, pal) }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--concepts"), i + 1 < args.count {
    let dir = args[i + 1]
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let sheet = CGContext(data: nil, width: 20 + palettes.count * 520, height: 520, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    sheet.setFillColor(rgb(240, 240, 244)); sheet.fill(CGRect(x: 0, y: 0, width: 20 + palettes.count * 520, height: 520))
    for (n, pal) in palettes.enumerated() {
        let img = icon(512, pal)
        writePNG(img, "\(dir)/concept_\(pal.name).png")
        sheet.draw(img, in: CGRect(x: 10 + n * 520, y: 4, width: 512, height: 512))
    }
    writePNG(sheet.makeImage()!, "\(dir)/contact_sheet.png")
    print("concepts written to \(dir)")
    exit(0)
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let set = "\(here)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    writePNG(icon(px, palettes[chosenPalette]), "\(set)/icon_\(name).png")
}
// Menubar template: black head silhouette on transparent (eyes and nose cut out), 18pt.
for (suffix, px) in [("", 18), ("@2x", 36)] {
    writePNG(render(px) { ctx in
        let k = CGFloat(px) / 640
        ctx.translateBy(x: CGFloat(px) / 2, y: CGFloat(px) / 2 - CGFloat(px) * 0.04)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: 0, y: -85)
        fillPath(ctx, sym(headLeft()), rgb(0, 0, 0)); fillPath(ctx, sym(earLeft()), rgb(0, 0, 0))
        ctx.setBlendMode(.clear)
        for sx: CGFloat in [-1, 1] { ctx.fillEllipse(in: CGRect(x: 100 * sx - 24, y: 30, width: 48, height: 64)) }
        ctx.fillEllipse(in: CGRect(x: -31, y: -217, width: 62, height: 42))
    }, "\(here)/MenuBarIcon\(suffix).png")
}
print("generated iconset + menubar PNGs (palette \(palettes[chosenPalette].name))")
