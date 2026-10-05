import Foundation
import Vision
import AppKit

let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true
try VNImageRequestHandler(cgImage: cg).perform([req])
let results: [VNRecognizedTextObservation] = req.results ?? []
let sorted = results.sorted { (a: VNRecognizedTextObservation, b: VNRecognizedTextObservation) -> Bool in
    return a.boundingBox.minY > b.boundingBox.minY
}
var out: [String] = []
for r in sorted {
    if let c = r.topCandidates(1).first { out.append(c.string) }
}
print(out.joined(separator: "\n"))
