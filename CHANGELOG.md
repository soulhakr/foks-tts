# Changelog

All notable changes to FOKS TTS. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/) (see `HANDOFF.md`). Add an entry here before running
`make release`; it checks that the version has one.

## [Unreleased]

## [0.2.1] - 2026-10-17

### Changed
- New installs use **Python 3.14** (was 3.13): `install.sh`, the Homebrew formula and the developer environment. The
  hash-locked requirements are unchanged (they already carry hashes for the 3.14 wheels), and speed and memory use are
  the same. Existing 3.13 environments keep working; `./install.sh --force` rebuilds one on 3.14. Python 3.15 is not
  supported yet: `mlx`, `numpy`, `scipy` and `spaCy` have no wheels for it.

## [0.2.0] - 2026-10-14

### Added
- Homebrew support (formula in the `soulhakr/tap` tap): `brew install soulhakr/tap/foks-tts`, then `foks-tts-setup`
  to copy the app into `~/Applications` and register the Services entry. The app now also looks for its Python
  environment and model in the Homebrew install when nothing is under `~/Library/Application Support/FOKS-TTS`
  (Settings overrides and an `install.sh` setup still take priority).
- `app/install_local.sh` accepts the path of the app to install; `install.sh` honors `UV_PYTHON_PREFERENCE` so a
  packager can use the system Python instead of uv's own.

## [0.1.1] - 2026-10-14

First tagged release (source only: build it with `./install.sh`).

### Added
- A macOS menu bar app that reads text aloud with the offline Kokoro-82M voice (MLX) and highlights each word in
  place: a window (Accessibility API, with OCR fallback), a dragged area, the whole screen, selected text, the
  clipboard image, or text sent from the Services menu. Global shortcuts, a floating pause/stop/speed bar, and a
  Settings window for the voice, speaking rate and reading options.
- Reading in sections: titles, body text and controls are told apart and separated by short pauses.
- An optional GPL pronunciation add-on (eSpeak NG), installed from Settings with a consent notice and never bundled.
- Engine locations in Settings, to use an existing Python environment or Kokoro model folder.
- An **About** section in Settings showing the version and build number; the version is also logged at each launch.
- `install.sh` and `uninstall.sh`; hash-locked dependencies; an MIT license and a generated third-party notices file.
- Developer tooling: a Makefile (`make` lists the tasks), a pytest suite including tests that check the lock files stay
  hash-locked and free of GPL packages and home paths, `make release`, `make screenshots` (the README images are
  rendered from the real views by `tools/render_screenshots.sh`), and GitHub Actions CI on macOS 14 and 15.
- Project documents: this changelog, `SECURITY.md` (private vulnerability reporting and what counts as in scope),
  `CONTRIBUTING.md`, and notes for assistants and new contributors (`CLAUDE.md`, `AGENTS.md`, `HANDOFF.md`).

### Fixed
- The voice worker's memory use: MLX's GPU buffer cache was unbounded (several GB after a few reads) and could exhaust
  memory. It is now capped at 256 MB and cleared after each read.
- Reading an area while another app (a screen share) was using the Neural Engine failed with an `e5rt` error; text
  recognition now retries on the CPU.
- A `Double` and `CGFloat` mix in the highlight rectangle that older Swift compilers reject as ambiguous.

### Removed
- The original command-line prototypes (`read_clipboard.sh`, `read_screen.swift`, `speak.py`, `speak_words.py`,
  `screen_to_speech.sh`, `vision_ocr.swift`). They are kept at the git tag `prototypes-v1`.
