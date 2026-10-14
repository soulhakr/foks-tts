# Contributing to FOKS TTS

Thanks for your interest. This is a small personal project, so changes are reviewed on a best-effort basis. Bug
reports, ideas and pull requests are all welcome. For security problems, see [SECURITY.md](SECURITY.md) and do not open a
public issue.

## Reporting a bug

Open an issue with:

- the version (*Settings > About*) and your macOS version and chip,
- what you did (which reading mode: window, area, screen, selection, clipboard or Services), and what you expected,
- the relevant lines from `~/Library/Logs/FOKS-TTS/foks.log`. The log holds events, counts and timings only, never the
  text it read, so it is safe to attach. Please do not attach screenshots of private content.

## What you need

An Apple silicon Mac on macOS 14 or newer, the Command Line Tools (`xcode-select --install`; Xcode is not needed), and
[uv](https://docs.astral.sh/uv/). Run `./install.sh` once to create the voice environment and download the model; the app
cannot be exercised without it.

## Working on the code

`make` lists the developer tasks:

```bash
make typecheck     # fast Swift compile check (does not rebuild, does not reset permissions)
make test          # typecheck, then the pytest suite in a hash-locked .venv-dev
make build         # build and ad-hoc sign the app
make check         # headless offline run of OCR, structure, audio and highlight against the existing build
make screenshots   # re-render the README images (after changing Settings)
```

`CLAUDE.md` is the project guide: architecture, the commands behind each task, the hard-won gotchas (read it before
touching capture, coordinates, Accessibility or the voice worker), and the decisions behind the design. `HANDOFF.md` is
the short orientation.

Things that will save you time:

- **Rebuilding resets macOS permissions.** The app is ad-hoc signed, so macOS treats every build as a new app. Batch your
  changes, then re-grant Accessibility and Screen Recording once (remove the old entry with the minus button first).
- **Hotkeys, pickers and permission flows can only be checked by hand.** Say in your pull request what you tested by
  hand and what you did not.
- **The Structure test needs a build.** `make test` skips the integration test unless the app is built and the model is
  installed; CI skips it too.

## Pull requests

- Keep them small and focused: one logical change, a clear subject in the imperative, and a body that explains *why*.
  Each commit should typecheck.
- Run `make test` before opening one. CI (macOS 14 and 15) must pass.
- Add or update tests for logic that has them (`tts_core.py`, `tests/`); `Structure` is tested through the built app.
- Update `CHANGELOG.md` under *Unreleased* for anything a user would notice, and the README or `CLAUDE.md` when you
  change behavior or add a gotcha.

## Project rules

- **Offline only.** No cloud services, telemetry or update checks. Network is used only by `install.sh`.
- **Dependencies are hash-locked** (`requirements/*.lock`, installed with `--require-hashes`). If you change a
  `requirements/*.txt`, regenerate its lock using the command in the file's header (`uv pip compile ... --generate-hashes`),
  replace any absolute path in the lock header with a placeholder, and run `make notices` to regenerate
  `THIRD_PARTY_NOTICES.md`. The lock tests in `tests/test_locks.py` check this.
- **Licensing.** FOKS TTS is MIT-licensed, and by contributing you agree your work is released under the same
  [license](LICENSE). Never bundle GPL code (the optional eSpeak NG add-on stays a separate, consented install) or model
  weights with their own terms (Gemma is not included and is not open source).
- **No private data in the repository:** no real screenshots or captures (the test image and demo are synthetic), no
  absolute home paths, no personal email addresses in commits. Config for the app goes through Settings, never through
  environment variables.
- **Brand.** The fox icon and palette follow [`brand/BRAND.md`](brand/BRAND.md) (a rust fox on forest green or sand;
  never blue or violet, never yellow-orange gradients, so it is not mistaken for other fox logos). Run
  `app/Icon/make_icon.swift` rather than editing the generated images.

## Releases

Releases are cut by the maintainer with `make release` (see `HANDOFF.md`): SemVer, a build number, a changelog entry, a
source tarball with a checksum, and a tag.
