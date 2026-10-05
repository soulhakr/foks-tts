import Foundation

/// The optional, separately licensed pronunciation add-on (phonemizer-fork, GPL-3.0-or-later, and
/// espeakng-loader, which bundles eSpeak NG, GPL-3.0). It is NOT bundled with the app: it is fetched from
/// PyPI only when the user asks, using the hash-locked file shipped in Resources.
enum OptionalPackages {
    static let packages = ["phonemizer-fork", "espeakng-loader"]

    static var lockFile: URL? { Bundle.main.resourceURL?.appendingPathComponent("optional-gpl-pronunciation.lock") }

    static func findUV() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func run(_ args: [String], completion: @escaping (String?) -> Void) {
        guard let uv = findUV() else { completion("Could not find `uv` (needed to install packages)."); return }
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: uv)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["UV_PYTHON_PREFERENCE"] = "only-managed"
            p.environment = env
            let pipe = Pipe()
            p.standardError = pipe
            p.standardOutput = pipe
            do { try p.run() } catch { DispatchQueue.main.async { completion("\(error)") }; return }
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            DispatchQueue.main.async { completion(p.terminationStatus == 0 ? nil : String(out.suffix(400))) }
        }
    }

    static func install(completion: @escaping (String?) -> Void) {
        guard let lock = lockFile, FileManager.default.fileExists(atPath: lock.path) else {
            completion("The add-on lock file is missing from the app bundle."); return
        }
        run(["pip", "install", "--python", Settings.pythonPath, "--require-hashes", "--no-deps", "-r", lock.path], completion: completion)
    }

    static func uninstall(completion: @escaping (String?) -> Void) {
        run(["pip", "uninstall", "--python", Settings.pythonPath] + packages, completion: completion)
    }
}
