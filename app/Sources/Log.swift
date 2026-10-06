import Foundation

/// Diagnostic log at ~/Library/Logs/FOKS-TTS/foks.log. Records events, counts and timings only, never screen text.
enum Log {
    static let url: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FOKS-TTS")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("foks.log")
    }()
    private static let queue = DispatchQueue(label: "foks.log")

    static func write(_ s: String) {
        queue.async {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            let line = "\(f.string(from: Date())) \(s)\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
