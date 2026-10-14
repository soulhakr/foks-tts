# Handoff

How to pick up FOKS TTS in a new session (human or AI assistant). Technical detail is in [CLAUDE.md](CLAUDE.md);
this file is the short orientation.

## Start here

1. Read [CLAUDE.md](CLAUDE.md), then [README.md](README.md), [ROADMAP.md](ROADMAP.md) and [brand/BRAND.md](brand/BRAND.md).
2. Verify the state before changing anything and report what you find:

```bash
git status && git log --oneline | head -5        # expect a clean tree on main
git config user.email                            # expect the GitHub noreply address
cd app && swiftc -swift-version 5 -typecheck Sources/*.swift && echo typecheck ok
pgrep -fl FOKS-TTS; tail -5 ~/Library/Logs/FOKS-TTS/foks.log   # is the app running; recent events
```

3. Ask before any push, force-push, history rewrite, or making the repository public.

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

## Recent state

- Voice worker memory is capped (MLX buffer cache limited to 256 MB, cleared after each read) and OCR falls back to the
  CPU when the Neural Engine is unavailable. Both passed basic hand testing; **not yet load-tested** (many long reads in
  a row; an area read during a screen share that actually triggers the Neural Engine failure).
- Not yet hand-tested: section pauses on the Accessibility path, the Electron/Chromium retry, `uninstall.sh`, and the
  Engine locations Choose.../Reset buttons.
