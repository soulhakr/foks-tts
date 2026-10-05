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
    static let kokoroVoices = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AI/kokoro/voices")
    static let pythonPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AI/mlx-env/bin/python").path

    @Published var voice: String { didSet { UserDefaults.standard.set(voice, forKey: "voice") } }
    @Published var rate: Double { didSet { UserDefaults.standard.set(rate, forKey: "rate") } }
    @Published var highlight: String { didSet { UserDefaults.standard.set(highlight, forKey: "highlight") } }
    @Published var showControls: Bool { didSet { UserDefaults.standard.set(showControls, forKey: "showControls") } }
    /// Where text comes from when a window is chosen: "auto" (accessibility, else OCR), "accessibility", "ocr".
    @Published var windowSource: String { didSet { UserDefaults.standard.set(windowSource, forKey: "windowSource") } }

    private init() {
        let d = UserDefaults.standard
        voice = d.string(forKey: "voice") ?? "af_heart"
        let r = d.double(forKey: "rate")
        rate = r == 0 ? 1.0 : min(2.0, max(0.5, r))
        highlight = d.string(forKey: "highlight") ?? "yellow"
        showControls = d.object(forKey: "showControls") as? Bool ?? true
        windowSource = d.string(forKey: "windowSource") ?? "auto"
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
