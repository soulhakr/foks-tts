# Handoff

How to pick up FOKS TTS in a new session (human or AI assistant). Technical detail is in [CLAUDE.md](CLAUDE.md);
this file is the short orientation.

## Start here

1. Read [CLAUDE.md](CLAUDE.md), then [README.md](README.md), [ROADMAP.md](ROADMAP.md) and [brand/BRAND.md](brand/BRAND.md).
2. Verify the state before changing anything and report what you find:

```bash
git status && git log --oneline | head -5        # expect a clean tree on main
git config user.email                            # expect the GitHub noreply address
make typecheck && echo typecheck ok              # `make` lists all developer tasks
pgrep -fl FOKS-TTS; tail -5 ~/Library/Logs/FOKS-TTS/foks.log   # is the app running; recent events
```

3. Ask before any push, force-push, history rewrite, or making the repository public.

## Identity and remote

- Commit identity (repo-local config): `soulhakr <577508+soulhakr@users.noreply.github.com>`. The machine's **global** git
  identity is a different one and must not be used here: if `git config user.email` inside the repo does not print the
  noreply address, stop and fix the local config before committing.
- `gh` is logged in as `soulhakr`. The remote is https://github.com/soulhakr/foks-tts and is **private**; it stays
  private until the maintainer says otherwise. The copyright holder in `LICENSE` is the handle `soulhakr`.

## Working style

- Short status and a recommendation with the reason; ask a question only when a decision is genuinely the
  maintainer's.
- The maintainer hand-tests hotkeys, pickers and permission flows. Read the log (`~/Library/Logs/FOKS-TTS/foks.log`)
  yourself rather than asking for details. Rebuilding resets macOS permission grants (ad-hoc signing), so batch changes
  and say when a re-grant will be needed.
- Commit in logical pieces; state plainly what was and was not tested.
- Flag legal, trademark and naming risks when you see them.
- Declined: creating a self-signed signing certificate; a VoiceOver-style "item under pointer" mode. Deferred: the paid
  Developer ID and notarized DMG.

## Where things are

| What | Where |
|---|---|
| Installed app | `~/Applications/FOKS TTS.app` (reinstall with `app/install_local.sh`, which quits the running app) |
| Runtime data | `~/Library/Application Support/FOKS-TTS` (venv and model; both can be overridden in Settings > Engine locations) |
| Logs | `~/Library/Logs/FOKS-TTS/foks.log`, `$TMPDIR/foks-tts-worker.log` |
| Planned work | `ROADMAP.md` and the "Open work" list in `CLAUDE.md` |

## Testing notes

- Displays can sit above or to the left of the primary one, which gives negative or large coordinates (see gotcha 3 in
  `CLAUDE.md`); test window and area reading on a second display when you change capture or overlay code.
- On a Mac with a notch, the menu bar icon can be hidden by a crowded bar or a menu bar manager; use the hotkeys.
- Only the Command Line Tools are required to build; the build does not use Xcode.app.
- `~/Library/Application Support/FOKS-TTS/venv` and `models/kokoro` may be **symlinks** on a developer machine (to an
  existing Python environment or model folder). `install.sh` leaves symlinks alone and `uninstall.sh` removes the link
  only; never `rm -rf` through one, and do not delete or restructure what it points to without asking.
- The old command-line prototypes were removed from `main`; they are at the git tag `prototypes-v1` (see `ROADMAP.md`,
  bring-your-own vision model). The app and installer do not use `mlx-vlm` or Gemma.

## Before the repository goes public

In addition to the checklist in `ROADMAP.md`:

- **GitHub keeps old commits.** After a history rewrite and force-push, GitHub can still serve the superseded commits by
  SHA until it garbage-collects. If anything in history had to be removed, delete and recreate the repository from the
  clean local history (cleanest), or ask GitHub Support to purge, before making it public.
- **Audit history** for anything personal or machine-specific. It should print nothing except known false positives
  (third-party license text in the lock files):

```bash
git log -p --all | grep -n -i -E "/Users/|$(whoami)|@(gmail|icloud|outlook|hotmail)\." | sort | uniq -c
git log --all --format='%an <%ae>' | sort -u      # expect only the noreply identity
```

- Also check the working tree and the generated files (`THIRD_PARTY_NOTICES.md`, lock headers) for absolute home paths.

## Versions and releases

- **SemVer** (`MAJOR.MINOR.PATCH`), staying at `0.y.z` until the app is stable and signed (1.0.0). Bump the **minor**
  version for new features or anything that affects users' saved settings, hotkeys, the install layout
  (`~/Library/Application Support/FOKS-TTS`) or the minimum macOS version; bump the **patch** version for fixes.
- In `app/Info.plist`, `CFBundleShortVersionString` is the version and `CFBundleVersion` is a whole **build number**
  that goes up by one for every release and is never reused (update tools compare it). `make bump` sets both.
- Flow: `make bump VERSION=0.1.0`, add a `## [0.1.0]` entry to `CHANGELOG.md` (the release refuses without one), commit and push, `make build` (the release runs the built-app test and refuses a stale
  build), `make release VERSION=0.1.0` (checks, tests, `dist/` tarball and checksum, local tag). It publishes nothing:
  push the tag and create the GitHub release by hand.

## Recent state

- Voice worker memory is capped (MLX buffer cache limited to 256 MB, cleared after each read) and OCR falls back to the
  CPU when the Neural Engine is unavailable. Both passed basic hand testing; **not yet load-tested** (many long reads in
  a row; an area read during a screen share that actually triggers the Neural Engine failure).
- Not yet hand-tested: section pauses on the Accessibility path, the Electron/Chromium retry, `uninstall.sh`, and the
  Engine locations Choose.../Reset buttons.
