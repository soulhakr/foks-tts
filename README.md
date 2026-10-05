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
| `test_screenshot.png` | Synthetic test image |

## Requirements

This repo holds only the glue code. The environment and models live outside it:

- `~/AI/mlx-env`: pinned Python 3.13 venv (uv-managed). Hash-locked install from
  `~/AI/mlx-env-requirements.lock` with `--require-hashes`.
- `~/AI/gemma3`: Gemma 3 12B 4-bit (from LM Studio's model store), used for VLM OCR.
- `~/AI/kokoro`: symlink to the cached `mlx-community/Kokoro-82M-bf16` snapshot.
- Setup details, versions, and rebuild steps: `~/AI/README.md`.

## Running offline

Scripts set `HF_HUB_OFFLINE=1`. To prove nothing touches the network:

```bash
sandbox-exec -p '(version 1)(allow default)(deny network*)' ./screen_to_speech.sh test_screenshot.png vision
```

## Known issues

- `mlx-audio` 0.4.4's Kokoro raises an input-dependent `[broadcast_shapes]` error on some
  text. `speak.py` works around it by chunking and retrying. Voices are loaded from a local
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
