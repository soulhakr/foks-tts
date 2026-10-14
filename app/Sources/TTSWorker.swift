import Foundation

/// Client for the resident Python Kokoro worker (app/tts_worker.py): JSON lines over stdin/stdout.
final class TTSWorker {
    static let shared = TTSWorker()

    private var proc: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var handlers: [Int: ([String: Any]) -> Void] = [:]
    private var nextID = 1
    private(set) var isReady = false
    private(set) var hasEspeak = false
    var onReadyChanged: (() -> Void)?
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foks-tts-worker.log")

    func start() {
        if let p = proc, p.isRunning { return }
        isReady = false
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("tts_worker.py"),
              FileManager.default.fileExists(atPath: script.path) else {
            log("worker script missing"); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Settings.pythonPath)
        p.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["FOKS_TTS_MODEL_DIR"] = Settings.modelDir.path
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        stdinHandle = inp.fileHandleForWriting
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { return }
            DispatchQueue.main.async { self?.ingest(d) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if let s = String(data: d, encoding: .utf8), !s.isEmpty { self?.log(s) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isReady = false
                self?.onReadyChanged?()
                self?.log("worker exited")
            }
        }
        do { try p.run(); proc = p } catch { log("could not start worker: \(error)") }
    }

    func stop() {
        stdinHandle?.closeFile()
        proc?.terminate()
        proc = nil
    }

    /// Relaunch the Python worker (e.g. after installing or removing the optional pronunciation add-on).
    func restart() {
        stop()
        isReady = false
        onReadyChanged?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.start() }
    }

    private func ingest(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if obj["ready"] as? Bool == true {
                isReady = true
                hasEspeak = obj["espeak"] as? Bool ?? false
                Log.write("worker ready, espeak=\(hasEspeak)")
                onReadyChanged?()
            } else if let id = obj["id"] as? Int {
                handlers[id]?(obj)
                if obj["final"] != nil || obj["error"] != nil || obj["cancelled"] != nil { handlers[id] = nil }
            }
        }
    }

    @discardableResult
    func speak(words: [String], pauses: [Double], voice: String, outDir: URL, handler: @escaping ([String: Any]) -> Void) -> Int {
        start()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        send(["cmd": "speak", "id": id, "words": words, "pauses": pauses, "voice": voice, "out_dir": outDir.path])
        return id
    }

    func cancel(_ id: Int) {
        handlers[id] = nil
        send(["cmd": "cancel", "id": id])
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        stdinHandle?.write(d + Data([0x0A]))
    }

    func log(_ s: String) {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close()
        } else {
            try? s.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
