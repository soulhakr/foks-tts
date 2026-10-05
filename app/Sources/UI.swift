import AppKit
import SwiftUI
import ApplicationServices

func rateLabel(_ r: Double) -> String { String(format: r == r.rounded() ? "%.0f×" : "%.2f×", r) }

/// Floating transport controls, modelled on the macOS Speech Controller: pause, stop, and a speed slider.
struct PillView: View {
    @ObservedObject var session: ReadingSession
    @ObservedObject var settings = Settings.shared
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { session.pauseResume() } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill").frame(width: 18)
            }.buttonStyle(.plain)
            Button(action: onStop) { Image(systemName: "stop.fill") }.buttonStyle(.plain)
            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
            Slider(value: $settings.rate, in: 0.5...2.0).frame(width: 110)
            Image(systemName: "hare.fill").foregroundStyle(.secondary)
            Text(rateLabel(settings.rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 340, height: 46)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Pop-up opened from the menubar item, like the macOS "Speaking Rate" control.
struct RateView: View {
    @ObservedObject var settings = Settings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speaking Rate").font(.headline)
            HStack {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                Slider(value: $settings.rate, in: 0.5...2.0, step: 0.05)
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button(rateLabel(r)) { settings.rate = r }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(abs(settings.rate - r) < 0.01 ? .accentColor : nil)
                }
            }
            Text("Now: \(rateLabel(settings.rate)). Applies immediately, even while reading.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 300)
    }
}

/// Permission and engine status shown in Settings. (An ObservableObject rather than @State, because
/// @State is a macro in recent SDKs and the Command Line Tools do not ship the SwiftUI macro plugin.)
final class StatusModel: ObservableObject {
    static let shared = StatusModel()
    @Published var axOK = AXText.trusted(prompt: false)
    @Published var scOK = CGPreflightScreenCaptureAccess()
    @Published var ready = TTSWorker.shared.isReady
    @Published var espeak = TTSWorker.shared.hasEspeak
    @Published var busy = false
    @Published var error: String?

    func refresh() {
        axOK = AXText.trusted(prompt: false)
        scOK = CGPreflightScreenCaptureAccess()
        ready = TTSWorker.shared.isReady
        espeak = TTSWorker.shared.hasEspeak
    }
}

struct SettingsView: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var status = StatusModel.shared
    var onPreview: () -> Void
    var onInstallAddon: () -> Void
    var onRemoveAddon: () -> Void

    var body: some View {
        Form {
            Section("Voice") {
                Picker("Voice", selection: $s.voice) {
                    ForEach(s.voiceGroups) { g in
                        Section(g.id) { ForEach(g.voices) { v in Text(v.name).tag(v.id) } }
                    }
                }
                Button("Preview voice", action: onPreview)
            }
            Section("Speaking rate") {
                HStack {
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                    Slider(value: $s.rate, in: 0.5...2.0, step: 0.05)
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    Text(rateLabel(s.rate)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Section("Reading") {
                Picker("Text source for windows", selection: $s.windowSource) {
                    Text("Automatic (accessibility, then OCR)").tag("auto")
                    Text("Accessibility only").tag("accessibility")
                    Text("OCR only").tag("ocr")
                }
                Picker("Highlight color", selection: $s.highlight) {
                    ForEach(Settings.highlightChoices, id: \.id) { Text($0.name).tag($0.id) }
                }
                Toggle("Show floating controls while reading", isOn: $s.showControls)
            }
            Section("Shortcuts") {
                LabeledContent("Read a window", value: "⌃⌥⌘W")
                LabeledContent("Read a selected area", value: "⌃⌥⌘A")
                LabeledContent("Read the whole screen", value: "⌃⌥⌘S")
                LabeledContent("Read clipboard image", value: "⌃⌥⌘V")
                LabeledContent("Pause / resume", value: "⌃⌥⌘P")
                LabeledContent("Stop", value: "⌃⌥⌘.")
            }
            Section("Extended pronunciation (optional)") {
                Text("Kokoro skips words that are missing from its dictionary, such as names, product names and jargon. An optional add-on teaches it to sound them out. It is a separate download under the GNU GPL v3 (eSpeak NG) and is not part of this app.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("eSpeak NG pronunciation") {
                    HStack {
                        Text(status.espeak ? "Installed" : "Not installed")
                            .foregroundStyle(status.espeak ? .green : .secondary)
                        if status.busy { ProgressView().controlSize(.small) }
                        else if status.espeak { Button("Remove…", action: onRemoveAddon) }
                        else { Button("Install…", action: onInstallAddon) }
                    }
                }
                if let e = status.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Section("Permissions & status") {
                LabeledContent("Voice engine", value: status.ready ? "Ready (offline)" : "Loading…")
                LabeledContent("Accessibility (read windows directly)") {
                    HStack {
                        Text(status.axOK ? "Granted" : "Not granted").foregroundStyle(status.axOK ? .green : .orange)
                        if !status.axOK { Button("Grant…") { _ = AXText.trusted(prompt: true); openPane("Privacy_Accessibility") } }
                    }
                }
                LabeledContent("Screen Recording (OCR of areas/screen)") {
                    HStack {
                        Text(status.scOK ? "Granted" : "Not granted").foregroundStyle(status.scOK ? .green : .orange)
                        if !status.scOK { Button("Grant…") { _ = CGRequestScreenCaptureAccess(); openPane("Privacy_ScreenCapture") } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 760)
        .onAppear { status.refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in status.refresh() }
    }

    private func openPane(_ name: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)") { NSWorkspace.shared.open(u) }
    }
}

/// Brief on-screen message near the pointer.
enum Toast {
    private static var panel: NSPanel?
    static func show(_ text: String) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: label.frame.height + 20)
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        box.layer?.cornerRadius = 10
        label.setFrameOrigin(NSPoint(x: 16, y: 10))
        box.addSubview(label)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .screenSaver; p.ignoresMouseEvents = true
        p.contentView = box
        let m = NSEvent.mouseLocation
        p.setFrameOrigin(NSPoint(x: m.x - size.width / 2, y: m.y + 24))
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { if panel === p { p.orderOut(nil) } }
    }
}
