# offline-tts

Read text from a screenshot aloud with a natural-sounding voice, **entirely on-device**.
OCR (local vision model or Apple Vision) feeds Kokoro-82M text-to-speech. No cloud, no
accounts, no network at run time. Apple silicon only.

```
image -> OCR (Gemma 3 via mlx-vlm | Apple Vision) -> text cleanup + chunking -> Kokoro (mlx-audio) -> WAV
```

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

## Requirements

This repo holds only the glue code. The environment and models live outside it:

- `~/AI/mlx-env`: pinned Python 3.13 venv (uv-managed). Hash-locked install from
  `~/AI/mlx-env-requirements.lock` with `--require-hashes`.
- `~/AI/gemma3`: Gemma 3 12B 4-bit (from LM Studio's model store), used for VLM OCR.
- `~/AI/kokoro`: symlink to the cached `mlx-community/Kokoro-82M-bf16` snapshot.
- Setup details, versions, and rebuild steps: `~/AI/README.md`.

## Read-aloud with word highlight (Shottr workflow)

1. Capture an area with Shottr (it is set to copy to the clipboard after capture).
2. Run `./read_clipboard.sh` (bind it to a hotkey with a Shortcut: *Run Shell Script* action,
   then add a keyboard shortcut in the shortcut's details).
3. OCR runs with Apple Vision (word-level boxes), Kokoro speaks, and the window highlights each
   word as it is spoken. Timing comes from Kokoro's own per-token timestamps.

Startup is about 10 s (uncompiled Swift plus model load); a 5 s passage takes about 15 s total.
Test without audio: `swift read_screen.swift --image test_screenshot.png --snapshots /tmp/frames --at 0.5,2,4`.

## Menubar app (OfflineTTS.app)

A native menubar app: read a **window**, a **selected area**, the **whole screen**, or the clipboard
image, with a highlight that follows each spoken word, a floating speed control, and a voice picker.

| Hotkey | Action |
|---|---|
| ⌃⌥⌘W / A / S | Read a window / a selected area / the whole screen |
| ⌃⌥⌘V | Read the clipboard image (works with Shottr's copy-to-clipboard) |
| ⌃⌥⌘P / ⌃⌥⌘. | Pause-resume / stop |

- **Windows are read through the macOS Accessibility API** (the text VoiceOver sees, with exact word
  positions), falling back to OCR. Areas and the full screen use Apple Vision OCR.
- A resident Python worker (`app/tts_worker.py`) keeps Kokoro loaded and streams audio chunk by chunk,
  so speech starts after the first sentence. Everything is offline.
- Settings: voice (all English Kokoro voices on disk), speaking rate (0.5x to 2x, adjustable live),
  window text source, highlight color, floating controls.
- Build: `app/build_app.sh` (uses full Xcode's toolchain; needs the Xcode.app SwiftUI macro plugin).
  Output `app/build/OfflineTTS.app`, ad-hoc signed.
- Permissions (System Settings > Privacy & Security): **Accessibility** to read windows directly,
  **Screen Recording** for area/screen OCR. Because the signature is ad-hoc, rebuilding changes the
  app's identity and macOS will ask again.
- Headless test: `OfflineTTS --read-image test_screenshot.png --snapshots /tmp/f --at 0.5,2,4`
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

## Licenses of what this uses

Kokoro weights Apache-2.0; mlx, mlx-vlm, mlx-audio MIT; Gemma 3 under Google's Gemma Terms
of Use; `phonemizer-fork` GPL and `num2words` LGPL.
