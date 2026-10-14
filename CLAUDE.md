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

Hand-tested by the maintainer on a notched MacBook plus two external monitors: window reading (Accessibility, with OCR
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
| `install.sh`, `uninstall.sh`, `app/build_app.sh`, `app/install_local.sh` | installer, build, local install and Services registration |
| `requirements/` | `core.lock` (69 hash-locked packages, no GPL) and the optional GPL add-on lock |
| `read_clipboard.sh`, `read_screen.swift`, `speak.py`, `speak_words.py`, `screen_to_speech.sh`, `vision_ocr.swift` | the original command-line prototypes the app grew from (kept; they use the FOKS venv; `screen_to_speech.sh`'s vision engine needs `OCR_MODEL` and `MLX_VLM_BIN` set, see below) |

Runtime layout: `~/Library/Application Support/FOKS-TTS/{venv,models/kokoro}`. The app reads **no environment
variables** (it is launched from Finder or launchd, which do not see the shell's). Instead, **Settings > Engine
locations** stores two optional overrides in UserDefaults (`pythonOverride`: an interpreter or a venv folder;
`modelDirOverride`: a Kokoro model folder), empty meaning the defaults above. The app sets `FOKS_TTS_MODEL_DIR` itself
when it starts the worker, restarts the worker (debounced 1 s) when either changes, and logs one line at each launch
with the locations in effect and whether each is a default or an override (plus any `FOKS_TTS_*` variables it ignores).
`FOKS_TTS_HOME` is read only by `install.sh`, `tts_core.py` and `read_screen.swift`. Python 3.13 (uv-managed), mlx
0.32.0, mlx-audio 0.4.4, misaki 0.9.4, spaCy 3.8.16.

## Commands

`make` lists the developer tasks (typecheck, build, install, check, notices, audit, clean); it is plain make with nothing
to install. The underlying commands:

```bash
./install.sh [--no-app] [--force]              # full install (venv from core.lock, pinned model + SHA-256, smoke test, app)
cd app && ./build_app.sh                       # build "build/FOKS TTS.app" (ad-hoc signed, Command Line Tools only)
cd app && ./install_local.sh                   # copy to ~/Applications, enable and register the Services entry
cd app && swiftc -swift-version 5 -typecheck Sources/*.swift     # fast compile check
# headless check of OCR, structure, audio and highlight (no permissions, works offline):
sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  "app/build/FOKS TTS.app/Contents/MacOS/FOKS-TTS" --read-image test_screenshot.png --snapshots /tmp/frames --at 0.5,2,4
# prints "STRUCT ..." lines (kind per word, pause set vs audible gap) and writes frame_N.png showing the highlight
```

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
    variables. Environment variables are fine only for terminal tools (`install.sh`, the legacy scripts).
16. **README screenshots are renders, not captures, and are static.** Regenerate them when Settings changes. Recipe
    (the harness is not in the repo): compile `app/Sources/*.swift` without `main.swift` plus a small `main.swift` that
    hosts `SettingsView` in an `NSHostingController`, sets `StatusModel` to ready/granted, applies
    `.environment(\.controlActiveState, .key)`, and writes `contentView.cacheDisplay` to a PNG (build a copy of
    `UI.swift` with the frame height raised so the whole dialog fits; light and dark via `app.appearance`). Run it with
    `CFFIXED_USER_HOME=/Users/Shared/demo` so no real username appears, over a demo home containing an executable
    `venv/bin/python`, `models/kokoro/config.json` and 54 empty `voices/<name>.safetensors` files, then crop the empty
    bottom with Pillow. Delete the demo home afterward. The menu bar image composites `MenuBarIcon@2x.png` on a light and
    a dark strip.
17. **His interactive zsh aliases `ls` (ANSI colors) and `mkdir` (verbose).** `$(ls ...)` yields escape codes in
    names; use `find` or `command ls` in anything scripted.

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
