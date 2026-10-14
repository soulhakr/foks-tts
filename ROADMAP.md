# Roadmap

Planned work, roughly in priority order. Nothing here is committed to a date.

## Bring-your-own vision model (optional OCR engine)

**Goal.** Let users read cluttered screens and layouts better than OCR alone, with a local vision-language model they
supply, while FOKS TTS stays fully offline and ships no model of its own.

**Why.** Apple Vision (the default) gives accurate text and exact word positions, but on a busy screen it returns every
label, menu and button in an approximate order. An early prototype (`screen_to_speech.sh`) used Gemma 3 12B through
`mlx-vlm` to transcribe only the main readable content in a sensible order. It worked, but was inconsistent on full
cluttered screens (output length varied with small prompt changes), takes about 15 s per read on an M4 Pro, and gives no
word positions.

**Why it is "bring your own".** Gemma is released under Google's Gemma Terms of Use: open weights, but not an open-source
license (it carries use restrictions), so FOKS TTS cannot bundle or redistribute it. More generally, every vision model
has its own license, so the user chooses a model and accepts its terms. FOKS TTS would ship none and recommend
permissively licensed ones (verify each model's license before use).

**Design sketch**
- A Settings choice for areas and the full screen: *Apple Vision* (default) or *Vision-language model*, plus a picker for
  a local MLX model folder the user already has (for example one downloaded with LM Studio).
- Installed on request, not by default, the same way as the GPL pronunciation add-on: a separate hash-locked
  `requirements/optional-vision.lock` for `mlx-vlm` (MIT) and its dependencies (about 250 MB extra, mostly OpenCV and
  Pillow), installed from Settings with a notice and consent.
- Keep the in-place highlight: vision models do not return word rectangles, so run Vision as well and align the
  model's cleaned text to Vision's word boxes (sequence alignment), using the model for reading order and filtering and
  Vision for geometry. Fall back to controls-only reading if alignment fails.
- A fixed prompt, temperature 0, and a length-robust parser, since prompt sensitivity was the main problem in the
  prototype.

**Done when** a cluttered full-screen capture reads in a sensible order more reliably than Apple Vision alone, with a
highlight, and the model path is entirely optional and offline.

## Better section detection

Sections (title, body, control) are detected today from accessibility roles where an app provides them (web
headings, buttons) and from type size and isolation for OCR. Native apps rarely mark headings, so a window title
inside a native app is read as body text. Ideas: use the font size that accessibility exposes for attributed text
(`AXFont`), and let the optional vision model above label sections (title, body, controls) semantically.

## Signed and notarized DMG, then a Homebrew cask (later)

Needs a paid Apple Developer ID, which is deferred. Today the app is built from source (`./install.sh`) and ad-hoc signed,
so macOS asks for permissions again after each rebuild; a Developer ID gives a stable identity and a download that opens
without warnings. The layout is already relocatable (`~/Library/Application Support/FOKS-TTS`) and the default install
contains no GPL code, so a DMG would not need a rewrite.

## Before the repository goes public

- Run a real trademark and name search for "FOKS TTS" and the fox logo (there is already an unrelated `foks` Homebrew cask).
- Run focus-group testing to workshop the app bundle name (the Finder caption, currently `FOKS TTS.app`) and the app
  icon before release. A bare "Foks" would read as the upstream FOKS key-service project, so test candidate names for
  distinctiveness as well as appeal. Changing the name touches `build_app.sh`, `install_local.sh`, `uninstall.sh` and
  the docs, and can reset macOS permission grants; the bundle ID (`local.soulhakr.foks-tts`) and the project name can
  stay as they are.
