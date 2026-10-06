import AppKit
import Vision

struct Word: Codable {
    let text: String
    let x: Double
    let y: Double      // normalized, origin top-left
    let w: Double
    let h: Double
    var kind: String = "body"      // "title", "body" or "ui" (see Structure)
    var pause: Double = 0           // seconds of silence after this word
}

/// OCR with word-level boxes via Apple Vision, in reading order (rows top to bottom, left to right).
/// `ignoreTopFraction` drops words in the top strip (e.g. the menu bar on a full-screen read).
func ocrWords(_ cg: CGImage, ignoreTopFraction: Double = 0, structure: Bool = true) throws -> [Word] {
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
    var blocks: [Block] = []
    for row in rows {
        for o in row.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
            guard let cand = o.topCandidates(1).first else { continue }
            let s = cand.string
            let firstIndex = words.count
            var i = s.startIndex
            while i < s.endIndex {
                while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
                if i >= s.endIndex { break }
                var j = i
                while j < s.endIndex, !s[j].isWhitespace { j = s.index(after: j) }
                let r = i..<j
                let rect: CGRect = (try? cand.boundingBox(for: r))?.boundingBox ?? o.boundingBox
                let w = Word(text: String(s[r]), x: Double(rect.minX), y: Double(1 - rect.maxY),
                             w: Double(rect.width), h: Double(rect.height))
                if w.y + w.h / 2 >= ignoreTopFraction { words.append(w) }
                i = j
            }
            if words.count > firstIndex {
                let bb = o.boundingBox
                blocks.append(Block(range: firstIndex..<words.count, kind: .body,
                                    rect: CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height),
                                    lineHeight: Double(bb.height), charCount: s.count))
            }
        }
    }
    if structure {
        Structure.classify(&blocks)
        Structure.applyPauses(&words, blocks)
    }
    return words
}
