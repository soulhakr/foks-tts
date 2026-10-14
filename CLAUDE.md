# CLAUDE.md: FOKS TTS

Context for an AI assistant (or a new contributor) picking this project up. Read this first, then `README.md`
(user-facing), `ROADMAP.md` (what is planned), and `brand/BRAND.md` (colors and guardrails).

## What this is

**FOKS TTS** ("Fully Offline Kokoro Speech"; tagline *What does the FOKS say?*) is a macOS menu bar app that reads
text on screen aloud in a natural neural voice, highlighting each word in place as it is spoken. Everything runs on
the Mac, offline, on Apple silicon. The maintainer's GitHub handle is `soulhakr`; the license is MIT (copyright
"soulhakr").

- Swift menu bar app (AppKit + SwiftUI, no Xcode project; built with `swiftc` from the Command Line Tools).
- A resident Python worker runs the Kokoro-82M voice through MLX and streams audio chunks with per-word timestamps.
- Reads: a window, a dragged area, the whole screen, selected text, the clipboard image, or text sent from the
  Services menu. Window and selection text comes from the Accessibility API (exact words and rectangles); area, screen
  and clipboard use Apple Vision OCR.

## State (at commit `989ad60`, pushed to the private remote 2026-10-13)

Hand-tested by the maintainer on a notched MacBook with external monitors: window reading (Accessibility, with OCR
fallback), area, whole screen, clipboard, selected-text reading (⌃⌥⌘T), the Services entry, the floating controls, voice
and rate settings, and the installer (from scratch in a temp location, and re-run on an existing setup).

**Engine locations (added 2026-10-13):** the Settings section was rendered and its path logic and worker override
were tested headlessly, and the maintainer saw the fields and green "Found: ..." status lines in the running app. Not
confirmed by hand: the Choose... and Reset buttons, the debounced worker restart after a change, and a launch from
Finder with an override set.

**Memory cap and OCR fallback (added 2026-10-13, commits `68b67eb`, `989ad60`):** the MLX cache cap (256 MB) and the CPU-only OCR
retry passed the maintainer's basic hand testing. **Not yet load-tested:** many long reads in a row (watch the worker's
memory), and an area read during a screen share that actually triggers the Neural Engine failure (the fallback has only been
exercised on the normal path).

**Not yet hand-tested:** the title/body/control section pauses on the *Accessibility* path (heading and button
detection; the OCR path is verified headlessly), the Electron/Chromium retry in `AXText.words`, and `uninstall.sh`
(syntax-checked only). After a rebuild the maintainer must re-grant permissions to test anything that needs them (see
gotcha 1).

## Architecture

```
 hotkey / menu / Services
        |
        v
 pick: window | area | screen | selection | clipboard     (Capture.swift picker overlays, ScreenCaptureKit)
        |
        v
 words + rects:  AXText.swift (Accessibility)   or   OCR.swift (Apple Vision)     -> [Word]
        |                                                                           Structure.swift tags each word
        v                                                                           title/body/ui and adds pauses
 TTSWorker.swift -- JSON lines --> app/tts_worker.py -> tts_core.py (Kokoro via mlx-audio)
        |                              chunks: wav + per-word spans [{i,start,end}]
        v
 Reader.swift: ReadingSession (AVAudioPlayer, live rate) + ReaderOverlay/HighlightView (in-place highlight)
```

| Path | Role |
|---|---|
| `app/Sources/main.swift` | `AppDelegate`: hotkeys (Carbon), menu, the read flows, Services provider, **headless test mode** |
| `app/Sources/Capture.swift` | window/area pickers (full-screen overlays), ScreenCaptureKit capture, CG<->AppKit coordinate helpers |
| `app/Sources/AXText.swift` | Accessibility reading: window walk (with Chromium/Electron retry), selection, headings, controls |
| `app/Sources/OCR.swift`, `Structure.swift` | Vision OCR with word boxes; classifier that marks title/body/ui and places pauses |
| `app/Sources/Reader.swift` | `ReadingSession` (stream, playback, rate, word index), `HighlightView`, `ReaderOverlay`, controls-only mode |
| `app/Sources/TTSWorker.swift`, `app/tts_worker.py`, `tts_core.py` | the voice worker client, protocol, and engine (chunking, per-word alignment, fixes) |
| `app/Sources/Settings.swift`, `UI.swift`, `OptionalPackages.swift`, `Log.swift` | settings model (including the Python and model-folder overrides and their status checks), SwiftUI settings and floating controller, the optional GPL add-on installer, diagnostic log |
| `app/Icon/make_icon.swift`, `brand/` | procedural icon and the palette (single source of truth: `brand/palette.json`) |
| `CHANGELOG.md` | Keep a Changelog format; `make release` requires an entry for the version being released |
| `install.sh`, `uninstall.sh`, `app/build_app.sh`, `app/install_local.sh` | installer, build, local install and Services registration |
| `requirements/` | `core.lock` (69 hash-locked packages, no GPL), the optional GPL add-on lock, and `dev.lock` (test tools, not shipped) |

Runtime layout: `~/Library/Application Support/FOKS-TTS/{venv,models/kokoro}`; if neither exists the app falls back to the
Homebrew formula's engine at `/opt/homebrew/opt/foks-tts/libexec/engine/{venv,models/kokoro}` (`Settings.brewEngine`).
The formula (`Formula/foks-tts.rb` in `soulhakr/homebrew-tap`) runs `install.sh --no-app` with `FOKS_TTS_HOME` set to that
folder, builds the app with `app/build_app.sh`, and installs a `foks-tts-setup` command that calls `app/install_local.sh`.

The app reads **no environment
variables** (it is launched from Finder or launchd, which do not see the shell's). Instead, **Settings > Engine
locations** stores two optional overrides in UserDefaults (`pythonOverride`: an interpreter or a venv folder;
`modelDirOverride`: a Kokoro model folder), empty meaning the defaults above. The app sets `FOKS_TTS_MODEL_DIR` itself
when it starts the worker, restarts the worker (debounced 1 s) when either changes, and logs one line at each launch
with the locations in effect and whether each is a default or an override (plus any `FOKS_TTS_*` variables it ignores).
`FOKS_TTS_HOME` is read only by `install.sh` and `tts_core.py`. Python 3.13 (uv-managed), mlx
0.32.0, mlx-audio 0.4.4, misaki 0.9.4, spaCy 3.8.16.

## Commands

`make` lists the developer tasks (typecheck, test, build, install, check, notices, screenshots, audit, bump, release, clean); it is plain make with nothing
to install. The underlying commands:

```bash
./install.sh [--no-app] [--force]              # full install (venv from core.lock, pinned model + SHA-256, smoke test, app)
cd app && ./build_app.sh                       # build "build/FOKS TTS.app" (ad-hoc signed, Command Line Tools only)
cd app && ./install_local.sh                   # copy to ~/Applications, enable and register the Services entry
cd app && swiftc -swift-version 5 -typecheck Sources/*.swift     # fast compile check
make test                                      # typecheck + pytest (37 tests; see below)
make bump VERSION=0.1.0                        # set the SemVer version and add 1 to the build number in app/Info.plist
make release VERSION=0.1.0                     # source release: checks, tests, dist/ tarball + sha256, LOCAL tag; publishes nothing
# headless check of OCR, structure, audio and highlight (no permissions, works offline):
sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  "app/build/FOKS TTS.app/Contents/MacOS/FOKS-TTS" --read-image test_screenshot.png --snapshots /tmp/frames --at 0.5,2,4
# prints "STRUCT ..." lines (kind per word, pause set vs audible gap) and writes frame_N.png showing the highlight
```

**Tests** (`tests/`, `pytest.ini`): `make test` runs pytest in `.venv-dev`, a project-local environment built from the
hash-locked `requirements/dev.lock` (source `requirements/dev.txt`; regenerate with the command in that file) and
rebuilt only when the lock changes. Nothing is installed globally or in the runtime venv; `make clean` removes it. The unit tests of `tts_core.py` (clean, chunking, alignment incl. skipped words, the
synth retry, pause padding, the SineGen patch, the eSpeak stand-in) replace MLX and mlx-audio with stubs in
`tests/conftest.py`, so they need no model and run in about a second. `Structure` is Swift, so `tests/test_structure.py`
drives the built app headlessly on `test_screenshot.png` and checks the title/body/control order and pauses; it is
skipped unless `make build` has been run and the FOKS venv and model are installed.

**CI** (`.github/workflows/ci.yml`): on pushes to main, pull requests and by hand, on macOS 14 (the supported minimum)
and 15: `zsh -n` on the shell scripts, `plutil -lint`, `make test` (typecheck, the unit tests and the lock-file checks in
`tests/test_locks.py`; the Structure integration test is skipped because there is no model), then `make build`. The
scripts are zsh, which shellcheck does not support, hence `zsh -n`. Actions are pinned to a commit SHA. macOS runners
cost 10x minutes on a private repository.

Logs: `~/Library/Logs/FOKS-TTS/foks.log` (events, counts, timings; never screen text) and `$TMPDIR/foks-tts-worker.log`.
Regenerate: icon (`cd app/Icon && swift make_icon.swift && iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf
AppIcon.iconset`), palette (`python3 brand/build_palette.py`), notices (`<venv>/bin/python tools/gen_notices.py`).
The demo GIF is made from headless snapshot frames of `test_screenshot.png` assembled with Pillow.

## Hard-won gotchas

1. **Ad-hoc signing resets macOS permissions on every rebuild** (identity = code hash). Accessibility and Screen
   Recording must be re-granted (remove the old entry with the minus button first). Batch changes into one rebuild
   and do not rebuild while someone is mid-test. A stable self-signed certificate would fix it; the maintainer
   declined to create one.
2. **Transparent overlay pixels are click-through.** macOS delivers mouse events to the window *underneath* pixels
   with alpha 0. The window picker once punched a fully clear hole over the hovered window, so clicks on the
   highlighted window never reached it. Fill with alpha >= ~0.02 instead.
3. **Coordinates.** AppKit is bottom-left of the primary screen, CG/Accessibility is top-left. Use `cgToAppKit` /
   `appKitToCG` (Capture.swift). Displays may sit above or left of the primary (y beyond the primary's height,
   negative x). Overlay highlights are drawn from global coordinates.
4. **Accessibility.** Set `AXManualAccessibility` and `AXEnhancedUserInterface` on the app; Chromium/Electron build
   their tree late (hence the retry). Per-word rects come from `AXBoundsForRange`. `_AXUIElementGetWindow` (private)
   maps an AX window to its CGWindowID, which rules out the App Store. The Services path needs no permission.
5. **mlx-audio 0.4.4 bugs, handled in `tts_core.py`:** (a) `SineGen._f02sine` yields one extra 300-sample frame when
   the audio length is a multiple of 300, raising `[broadcast_shapes]` (patched at import); (b) it imports
   `misaki.espeak` unconditionally and will not start without it (a stand-in module is registered when the optional
   GPL add-on is absent); (c) always pass the voice as an absolute path to `voices/<name>.safetensors`, or it fetches
   from another repo; (d) British voices (`b*`) need `lang_code="b"`.
6. **Kokoro behavior.** It leaves about 0.5 s between chunks, so configured pauses are on top of that. Without eSpeak,
   out-of-dictionary words (names, jargon) are silently skipped, so alignment must still consume their characters or
   every later word drifts (implemented in `align`). Word timing comes from the pipeline's per-token `start_ts`/`end_ts`.
7. **Vision OCR.** Observation boxes are tight to glyphs, so height barely separates a title from body text; width per
   character is the strong signal (`Structure.classify`). It can misread a lone "A" as a Cyrillic look-alike.
8. **SwiftUI `@State` is a macro** in recent SDKs and the Command Line Tools lack its plugin: do not use it; use
   `ObservableObject` plus `@StateObject`/`@ObservedObject`. Compile with `-swift-version 5`.
9. **Services** come from `NSServices` in `Info.plist` and are only discovered for apps in standard locations
   (`~/Applications`); `pbs -update` refreshes. New services may need ticking once in System Settings > Keyboard >
   Keyboard Shortcuts > Services. Test without UI via `NSPerformService("Read Aloud with FOKS TTS", pasteboard)`.
10. **A venv under `/private/tmp` makes the eSpeak add-on crash** (eSpeak cannot find its data; cause not understood).
    Keep real environments under `$HOME`.
11. **Core Graphics paths:** filling a union of mirrored shapes in one path cancels overlaps (opposite winding); fill
    each shape separately (the icon generator does).
12. **`.gitignore` blocks `*.png`** (to keep desktop screenshots out) except explicit allowances; add an exception for
    any new image that must be committed (the three README images in `docs/` are allowlisted).
13. **No absolute home paths in committed files.** `uv pip compile` writes the command, including `--python <abs
    path>`, into lock headers; replace it with a placeholder before committing (a leaked username once had to be
    scrubbed from history).
14. `UV_PYTHON_PREFERENCE=only-managed` keeps uv from borrowing Homebrew's or the system Python.
15. **Config for the app goes through Settings, never the environment.** A Finder or launchd launch has no shell
    variables. Environment variables are fine only for terminal tools such as `install.sh`.
16. **README screenshots are renders, not captures, and are static.** Regenerate them with `make screenshots`
    (`tools/render_screenshots.sh`) whenever Settings changes, then commit the three images in `docs/`. The harness
    (`tools/screenshots/main.swift`) compiles the app sources without `main.swift`, hosts `SettingsView` in an
    `NSHostingController` at 2x with fixed status values (`StatusModel.frozen`, `SettingsView.height`), crops the empty
    bottom, and composites the menu bar icon on a light and a dark strip. The script runs it over a demo home
    (`/Users/Shared/foks-demo`, deleted afterwards, with an executable `venv/bin/python`, `models/kokoro/config.json` and
    one empty file per voice) via `CFFIXED_USER_HOME`, so no real username appears in the paths.
17. **Shell aliases change output.** An interactive zsh may alias `ls` (ANSI colors) or `mkdir` (verbose), so `$(ls ...)`
    yields escape codes in names; in anything scripted use `find`, `command ls` or `command mkdir`.

## Conventions

- Commit with the repo-local git identity (`soulhakr`, GitHub noreply address); check `git config user.email` inside the
  repo before committing. Push, force-push, history rewrites and making the repository public happen only on the
  maintainer's explicit instruction.
- Small logical commits; imperative subject, a body that says *why*, and the trailer
  `Co-Authored-By: Claude <noreply@anthropic.com>` when an assistant wrote it. Typecheck each commit.
- When one file mixes concerns across commits, construct each commit's file contents rather than relying on
  `git add -p` (non-interactive here).
- Say plainly what was and was not hand-tested; the maintainer verifies hotkeys, pickers and permission flows by hand.
- Never commit real desktop screenshots or captures (the test image and demo are synthetic), and keep dependencies
  hash-locked (`--require-hashes`).
- Regenerate `THIRD_PARTY_NOTICES.md` whenever the requirements change.

## Decisions and why

- **Offline only.** No cloud TTS, no telemetry; network is used only by `install.sh`.
- **Unsandboxed, source-first distribution.** Reading other apps needs Accessibility and a spawned Python worker, so no
  Mac App Store. Today: clone and `./install.sh` (built locally, no Gatekeeper friction). A signed and notarized DMG
  and a Homebrew cask are planned later (need a paid Developer ID).
- **GPL is never bundled.** `phonemizer-fork` and `espeakng-loader` (eSpeak NG) are an optional add-on installed from
  Settings with a consent dialog; `core.lock` has none. **Gemma 3** (Gemma Terms of Use, not open source) is never
  bundled; an optional bring-your-own vision model is planned (ROADMAP.md).
- **Name.** "FOKS TTS" (token `foks-tts`) because an unrelated `foks` Homebrew cask exists; app and data folder names are
  distinct for the same reason.
- **Brand.** Friendly rust-colored red fox on forest green (dark) or sand (light); palette in `brand/palette.json`.
  Stay distinct from Firefox (bright yellow-orange gradient fox on a blue/purple globe) and GitLab (orange fox): no
  yellow-orange gradients, never blue/violet backgrounds. No white kitsune mask or fake Japanese text (cultural
  sensitivity). The Dr. Seuss wink stays in the README only, not in the app name, logo or marketing.
- **Considered and declined:** a VoiceOver-style "read the item under the pointer" mode (selection reading plus the
  Services entry cover the intent); creating a self-signed signing certificate.
- **Sections and pauses.** Titles, body and controls are told apart and separated by short silences (title 0.35 s, kind
  change 0.3 s, paragraph 0.2 s, on top of Kokoro's ~0.5 s). Settings can turn the pauses and control-reading off.

## Open work

1. Hand-test the Accessibility section/pauses path (web headings, window controls) and the Electron retry; confirm that
   reading controls is not too noisy in busy apps.
2. Bring-your-own vision model (see ROADMAP.md): an optional `mlx-vlm` add-on; use Vision for word boxes and the model
   for reading order and section labels, aligned to keep the highlight.
3. Better title detection in native apps (e.g. font size from accessibility attributed strings).
4. Configurable hotkeys (they are fixed at Control-Option-Command plus W, A, S, T, V, P, and period).
5. Before the repository goes public: see the checklist in ROADMAP.md (name/trademark search for "FOKS TTS" and the fox
   logo, focus-group testing of the bundle name and icon (a bare "Foks" would read as the upstream FOKS project), a final
   scan of history for anything that should not be permanent).
6. Later: signed and notarized DMG, then a Homebrew cask.
