import AppKit
import SwiftUI

struct VoiceInfo: Identifiable, Hashable {
    let id: String          // e.g. "af_heart"
    let name: String        // "Heart"
    let group: String       // "American, female"
}

struct VoiceGroup: Identifiable {
    let id: String
    let voices: [VoiceInfo]
}

final class Settings: ObservableObject {
    static let shared = Settings()
    /// ~/Library/Application Support/FOKS-TTS: `venv` (Python environment) and `models/kokoro` (model and voices).
    /// Both locations can be overridden in Settings (stored in `pythonOverride` / `modelDirOverride`).
    static let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FOKS-TTS")
    static let defaultPythonPath = home.appendingPathComponent("venv/bin/python").path
    static let defaultModelDir = home.appendingPathComponent("models/kokoro").path

    /// Python interpreter used for the voice engine. The override may name the interpreter itself or a
    /// virtual-environment folder (then `bin/python` inside it is used).
    static var pythonPath: String { resolvePython(shared.pythonOverride) }
    static var modelDir: URL { URL(fileURLWithPath: resolveModelDir(shared.modelDirOverride)) }
    static var kokoroVoices: URL { modelDir.appendingPathComponent("voices") }

    static func expand(_ raw: String) -> String {
        (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    static func resolvePython(_ raw: String) -> String {
        let p = expand(raw)
        if p.isEmpty { return defaultPythonPath }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { return p + "/bin/python" }
        return p
    }

    static func resolveModelDir(_ raw: String) -> String {
        let p = expand(raw)
        return p.isEmpty ? defaultModelDir : p
    }

    /// Short description of what is (or is not) at the given Python location, for the Settings screen.
    static func pythonStatus(_ raw: String) -> (ok: Bool, text: String) {
        let path = resolvePython(raw)
        return FileManager.default.isExecutableFile(atPath: path) ? (true, "Found: \(path)") : (false, "Not found: \(path)")
    }

    static func modelStatus(_ raw: String) -> (ok: Bool, text: String) {
        let dir = resolveModelDir(raw)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir + "/config.json") else { return (false, "No config.json in \(dir)") }
        let n = ((try? fm.contentsOfDirectory(atPath: dir + "/voices")) ?? []).filter { $0.hasSuffix(".safetensors") }.count
        return n > 0 ? (true, "Found: \(dir) (\(n) voices)") : (false, "No voices folder in \(dir)")
    }

    /// One line for the launch log: which Python and model folder are in effect and where each came from, plus a
    /// note if FOKS_TTS_* variables are present (the app ignores them; use the Settings fields instead).
    static func locationSummary() -> String {
        func source(_ raw: String) -> String { expand(raw).isEmpty ? "default" : "Settings override" }
        var line = "engine: python=\(pythonPath) [\(source(shared.pythonOverride))] model=\(modelDir.path) [\(source(shared.modelDirOverride))]"
        let ignored = ProcessInfo.processInfo.environment.keys.filter { $0.hasPrefix("FOKS_TTS_") }.sorted()
        if !ignored.isEmpty { line += "; ignoring environment: \(ignored.joined(separator: ", "))" }
        return line
    }

    /// Empty means "use the default location".
    @Published var pythonOverride: String { didSet { UserDefaults.standard.set(pythonOverride, forKey: "pythonOverride") } }
    @Published var modelDirOverride: String { didSet { UserDefaults.standard.set(modelDirOverride, forKey: "modelDirOverride") } }

    @Published var voice: String { didSet { UserDefaults.standard.set(voice, forKey: "voice") } }
    @Published var rate: Double { didSet { UserDefaults.standard.set(rate, forKey: "rate") } }
    @Published var highlight: String { didSet { UserDefaults.standard.set(highlight, forKey: "highlight") } }
    @Published var showControls: Bool { didSet { UserDefaults.standard.set(showControls, forKey: "showControls") } }
    /// Pause briefly between titles, body text and buttons or other controls.
    @Published var structurePauses: Bool { didSet { UserDefaults.standard.set(structurePauses, forKey: "structurePauses") } }
    /// Read button, checkbox and similar control labels when reading a window through Accessibility.
    @Published var readControls: Bool { didSet { UserDefaults.standard.set(readControls, forKey: "readControls") } }
    /// Where text comes from when a window is chosen: "auto" (accessibility, else OCR), "accessibility", "ocr".
    @Published var windowSource: String { didSet { UserDefaults.standard.set(windowSource, forKey: "windowSource") } }

    private init() {
        let d = UserDefaults.standard
        voice = d.string(forKey: "voice") ?? "af_heart"
        pythonOverride = d.string(forKey: "pythonOverride") ?? ""
        modelDirOverride = d.string(forKey: "modelDirOverride") ?? ""
        let r = d.double(forKey: "rate")
        rate = r == 0 ? 1.0 : min(2.0, max(0.5, r))
        highlight = d.string(forKey: "highlight") ?? "yellow"
        showControls = d.object(forKey: "showControls") as? Bool ?? true
        windowSource = d.string(forKey: "windowSource") ?? "auto"
        structurePauses = d.object(forKey: "structurePauses") as? Bool ?? true
        readControls = d.object(forKey: "readControls") as? Bool ?? true
    }

    static let highlightChoices: [(id: String, name: String, color: NSColor)] = [
        ("yellow", "Yellow", .systemYellow), ("green", "Green", .systemGreen),
        ("blue", "Blue", .systemBlue), ("pink", "Pink", .systemPink), ("orange", "Orange", .systemOrange),
    ]
    var highlightColor: NSColor { Settings.highlightChoices.first { $0.id == highlight }?.color ?? .systemYellow }

    /// English Kokoro voices found on disk (af/am = American, bf/bm = British).
    var voices: [VoiceInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Settings.kokoroVoices.path)) ?? []
        let ids = Set(files.filter { $0.hasSuffix(".safetensors") }.map { String($0.dropLast(".safetensors".count)) })
        return ids.sorted().compactMap { id in
            guard id.count > 3, let a = id.first, let g = id.dropFirst().first, id.dropFirst(2).first == "_",
                  "ab".contains(a), "fm".contains(g) else { return nil }
            let accent = a == "a" ? "American" : "British"
            let gender = g == "f" ? "female" : "male"
            return VoiceInfo(id: id, name: String(id.dropFirst(3)).capitalized, group: "\(accent), \(gender)")
        }
    }

    var voiceGroups: [VoiceGroup] {
        let all = voices
        let order = ["American, female", "American, male", "British, female", "British, male"]
        return order.compactMap { g in
            let v = all.filter { $0.group == g }
            return v.isEmpty ? nil : VoiceGroup(id: g, voices: v)
        }
    }

    func voiceName(_ id: String) -> String {
        voices.first { $0.id == id }.map { "\($0.name) (\($0.group))" } ?? id
    }
}
