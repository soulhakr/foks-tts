# FOKS TTS

*What does the FOKS say?* — **F**ully **O**ffline **K**okoro **S**peech (`foks-tts`).

> Would you read it in a box?
> Would you read it with a FOKS?
>
> *In a box, with a FOKS: yes! Drag a box around any text on your screen and FOKS TTS reads it back to you,
> offline, in a natural voice, following along word by word.*
>
> (With apologies to Dr. Seuss.)

Read text from a screenshot aloud with a natural-sounding voice, **entirely on-device**.
OCR (local vision model or Apple Vision) feeds Kokoro-82M text-to-speech. No cloud, no
accounts, no network at run time. Apple silicon only.

```
image -> OCR (Gemma 3 via mlx-vlm | Apple Vision) -> text cleanup + chunking -> Kokoro (mlx-audio) -> WAV
```

## Install

Requirements: an Apple silicon Mac on macOS 14 or newer, the Command Line Tools (`xcode-select --install`),
and [uv](https://docs.astral.sh/uv/) (the script installs it with Homebrew if you have Homebrew).

```bash
git clone <this repo> && cd foks-tts
./install.sh
```

It creates a uv-managed Python 3.13 environment from the hash-locked `requirements/core.lock`, downloads the
Kokoro model at a pinned revision and verifies its SHA-256, speaks a test sentence offline, then builds
`FOKS TTS.app` and installs it to `~/Applications` (including the Services-menu entry). Everything lives in
`~/Library/Application Support/FOKS-TTS`. Options: `--no-app` (environment and model only), `--force`
(rebuild). It is safe to re-run, and it leaves a symlinked developer setup alone. `./uninstall.sh` removes it
(it asks before deleting the environment and model).

After installing, open the app, grant Accessibility (and Screen Recording for area and full-screen
reading) in its Settings, and try Control-Option-Command-T on some selected text.

## Files

| File | Purpose |
|---|---|
| `screen_to_speech.sh` | Pipeline: `./screen_to_speech.sh <image.png> [vlm\|vision]`, writes `<image>_speech.wav` (`PLAY=1` to play) |
| `speak.py` | Kokoro driver: cleans symbols, chunks text, retries failed chunks by splitting. Reads text on stdin |
| `vision_ocr.swift` | Apple Vision OCR, run uncompiled (`swift vision_ocr.swift img.png`) so no binary is installed |
| `read_clipboard.sh` / `read_screen.swift` | Read the clipboard image aloud in a small window that **highlights the current word** (Esc quits, Space pauses) |
| `tts_core.py` / `speak_words.py` | Kokoro helpers (cleanup, chunking, per-word timestamps, the SineGen fix) and the one-shot CLI used by `read_screen.swift` |
| `app/` | The menubar app: Swift sources, `tts_worker.py`, `Info.plist`, `build_app.sh` |
| `test_screenshot.png` | Synthetic test image |

## Read-aloud with word highlight (Shottr workflow)

1. Capture an area with Shottr (it is set to copy to the clipboard after capture).
2. Run `./read_clipboard.sh` (bind it to a hotkey with a Shortcut: *Run Shell Script* action,
   then add a keyboard shortcut in the shortcut's details).
3. OCR runs with Apple Vision (word-level boxes), Kokoro speaks, and the window highlights each
   word as it is spoken. Timing comes from Kokoro's own per-token timestamps.

Startup is about 10 s (uncompiled Swift plus model load); a 5 s passage takes about 15 s total.
Test without audio: `swift read_screen.swift --image test_screenshot.png --snapshots /tmp/frames --at 0.5,2,4`.

## Menubar app (FOKS TTS.app)

A native menubar app: read a **window**, a **selected area**, the **whole screen**, or the clipboard
image, with a highlight that follows each spoken word, a floating speed control, and a voice picker.

| Hotkey | Action |
|---|---|
| ⌃⌥⌘W / A / S | Read a window / a selected area / the whole screen |
| ⌃⌥⌘T | Read the text currently selected in any app (like macOS Speak Selection) |
| ⌃⌥⌘V | Read the clipboard image (works with Shottr's copy-to-clipboard) |
| ⌃⌥⌘P / ⌃⌥⌘. | Pause-resume / stop |

- **Windows are read through the macOS Accessibility API** (the text VoiceOver sees, with exact word
  positions), falling back to OCR. Areas and the full screen use Apple Vision OCR.
- **Selected text** (⌃⌥⌘T, or the menu's *Read Selected Text*) uses the Accessibility API like Speak Selection
  does, and highlights in place when the app reports where the words are. Apps that do not expose their
  selection can use the Services entry below.
- **Services menu:** run `app/install_local.sh` (copies the app to `~/Applications` and refreshes the Services
  cache), then in any app select text, right-click, and choose *Services > Read Aloud with FOKS TTS*. It needs no
  permissions, because the app you are in hands over the text. If it does not show up, tick it once under System
  Settings > Keyboard > Keyboard Shortcuts > Services > Text (macOS may not enable new services on its own); that
  pane is also where you assign a keyboard shortcut. It shows the floating controls but no on-screen highlight.
- A resident Python worker (`app/tts_worker.py`) keeps Kokoro loaded and streams audio chunk by chunk,
  so speech starts after the first sentence. Everything is offline.
- Settings: voice (all English Kokoro voices on disk), speaking rate (0.5x to 2x, adjustable live),
  window text source, highlight color, floating controls.
- Build: `app/build_app.sh` (uses full Xcode's toolchain; needs the Xcode.app SwiftUI macro plugin).
  Output `app/build/FOKS TTS.app`, ad-hoc signed.
- Permissions (System Settings > Privacy & Security): **Accessibility** to read windows directly,
  **Screen Recording** for area/screen OCR. Because the signature is ad-hoc, rebuilding changes the
  app's identity and macOS will ask again.
- Headless test: `FOKS-TTS --read-image test_screenshot.png --snapshots /tmp/f --at 0.5,2,4`
  writes frames showing which word is highlighted at those times.

## Optional GPL pronunciation add-on

Kokoro skips words that are missing from its dictionary (names, product names, jargon). An optional
add-on teaches it to sound them out using eSpeak NG. Those packages are **GPL-licensed**, so they are
**not part of the default install** and are never bundled:

- Default install: `requirements/core.lock` (69 packages, no GPL code, about 460 MB).
- Add-on: `requirements/optional-gpl-pronunciation.lock` (`phonemizer-fork` GPL-3.0+, `espeakng-loader`
  which bundles eSpeak NG GPL-3.0, plus 20 small helper packages). Install and remove it from
  *Settings > Extended pronunciation* in the app, which shows the license notice and asks first. Or:
  `uv pip install --python <venv>/bin/python --require-hashes --no-deps -r requirements/optional-gpl-pronunciation.lock`
- `tts_core.py` registers a stand-in for `misaki.espeak` when the add-on is absent (mlx-audio 0.4.4
  otherwise refuses to start without it), and aligns word timing correctly around skipped words.
- Verified in a fresh venv built from the hash-locked files: core only runs (`espeak = False`), the add-on
  installs and enables `espeak = True`, removal reverts it, and a corrupted hash is rejected.

## Brand

Colors, themes, contrast checks and guardrails are in [`brand/BRAND.md`](brand/BRAND.md); the single source of
truth is `brand/palette.json` (rust on forest green for dark, rust on sand for light), and the icon generator reads it.

## Icon

A friendly red fox with a speech bubble, drawn procedurally by `app/Icon/make_icon.swift`
(`swift make_icon.swift`, then `iconutil -c icns` as in the script header). Two palettes are included
(`rust-forest` is the default, `rust-sand` is the light variant); change
`chosenPalette` to switch. The fox is a deeper rust/copper than Firefox's yellow-orange and sits on green,
charcoal or cream, never blue or purple, so the app is not mistaken for Firefox/Mozilla or GitLab.

## Running offline

Scripts set `HF_HUB_OFFLINE=1`. To prove nothing touches the network:

```bash
sandbox-exec -p '(version 1)(allow default)(deny network*)' ./screen_to_speech.sh test_screenshot.png vision
```

## Known issues

- `mlx-audio` 0.4.4's Kokoro raised an input-dependent `[broadcast_shapes]` error (a float rounding
  bug in `SineGen._f02sine` when the audio length is a multiple of 300 samples). `tts_core.py` patches
  it at import by trimming the sine wave to the pitch-curve length; chunk-splitting remains as a fallback. Voices are loaded from a local
  path because the library otherwise defaults to fetching from a different repo.
- Gemma 3 is inconsistent on cluttered full screens; use a cropped region. Apple Vision is
  exhaustive but noisy on UI.
- `misaki` declares `Python <3.13`; it works on 3.13 but is outside upstream support.
- Interpreted Swift recompiles on every run (about 9 to 36 s).

## Privacy

Never commit screenshots of a live desktop. `.gitignore` excludes `real_*`, all PNGs except
`test_screenshot.png`, and generated audio.

## License

FOKS TTS is released under the [MIT License](LICENSE). It uses third-party packages, a model and data under
their own licenses; they are listed with full texts in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
(generated by `tools/gen_notices.py`). Two things to know:

- **GPL code is never bundled.** The optional pronunciation add-on (`phonemizer-fork`, GPL-3.0-or-later, and
  eSpeak NG via `espeakng-loader`, GPL-3.0) is a separate download you can choose to install from Settings.
- **Gemma is not included.** The experimental `screen_to_speech.sh` can use a local Gemma 3 copy you already
  have; Gemma's own terms (Google's Gemma Terms of Use) apply to it.
- The Kokoro model's training data includes two datasets that require attribution (Koniwa, SIWIS); the credits
  are in the notices file.
