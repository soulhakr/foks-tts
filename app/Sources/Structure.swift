import Foundation

/// What a run of text is for. The reader pauses briefly when it moves from one kind to another.
enum Kind: String { case title, body, ui }

/// A run of words that belong together: one OCR text line, or one accessibility element.
struct Block {
    var range: Range<Int>        // indexes into the words array
    var kind: Kind
    var rect: CGRect             // normalized to the captured area, origin top-left
    var lineHeight: Double       // normalized height of one line of text
    var charCount: Int = 0       // characters in the line (OCR only; used to estimate type size)
}

enum Structure {
    // Silence (seconds) added after the last word of a block. The voice already leaves about 0.5 s between
    // chunks, so these are on top of that: audible gaps come out around 0.85 / 0.8 / 0.7 / 0.65 s.
    static let afterTitle = 0.35
    static let onKindChange = 0.3
    static let paragraph = 0.2
    static let betweenControls = 0.15

    /// Guess title / body / ui for OCR lines from text size, length and isolation. (The Accessibility path knows
    /// the kinds from element roles and does not need this.)
    static func classify(_ blocks: inout [Block]) {
        guard !blocks.isEmpty else { return }
        // Type size is estimated from two signals: the line's box height, and the width per character (which
        // separates large and bold text much more strongly, since Vision's boxes are tight to the glyphs).
        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        let reference = blocks.filter { $0.range.count >= 4 }.isEmpty ? blocks : blocks.filter { $0.range.count >= 4 }
        let medHeight = median(reference.map { $0.lineHeight })
        let medChar = median(reference.filter { $0.charCount >= 6 }.map { $0.rect.width / Double($0.charCount) }.nonEmpty ?? [0])
        func sizeRatio(_ b: Block) -> Double {
            let h = b.lineHeight / medHeight
            guard medChar > 0, b.charCount >= 6 else { return h }
            return (h * (b.rect.width / Double(b.charCount)) / medChar).squareRoot()        // geometric mean of the two ratios
        }
        for i in blocks.indices {
            let b = blocks[i]
            if sizeRatio(b) >= 1.3 { blocks[i].kind = .title; continue }                  // clearly larger text
            guard b.range.count <= 3, b.rect.width < 0.35 else { continue }               // only short lines can be labels
            let gapPrev = i == 0 ? Double.infinity : b.rect.minY - blocks[i - 1].rect.maxY
            let gapNext = i == blocks.count - 1 ? Double.infinity : blocks[i + 1].rect.minY - b.rect.maxY
            let apartBefore = gapPrev >= 0.9 * b.lineHeight, apartAfter = gapNext >= 0.9 * b.lineHeight
            if i == 0, apartAfter { blocks[i].kind = .title }                            // a short line leading the content
            else if apartBefore, apartAfter { blocks[i].kind = .ui }                      // stands alone: a button or label
        }
    }

    /// Record each word's kind and put a pause after the last word of a block when the kind changes or a new
    /// paragraph starts.
    static func applyPauses(_ words: inout [Word], _ blocks: [Block]) {
        for b in blocks { for i in b.range where i < words.count { words[i].kind = b.kind.rawValue } }
        for i in 0..<max(0, blocks.count - 1) {
            let a = blocks[i], b = blocks[i + 1]
            guard let last = a.range.last, last < words.count else { continue }
            var pause = 0.0
            if a.kind != b.kind {
                pause = a.kind == .title ? afterTitle : onKindChange
            } else if b.rect.minY - a.rect.maxY > 0.9 * a.lineHeight {                    // a clear vertical gap
                pause = a.kind == .ui ? betweenControls : paragraph
            }
            words[last].pause = pause
        }
    }
}

private extension Array {
    /// nil when empty, so `a.nonEmpty ?? fallback` reads naturally.
    var nonEmpty: [Element]? { isEmpty ? nil : self }
}
