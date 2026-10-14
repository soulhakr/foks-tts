# AGENTS.md

Instructions for AI coding agents working in this repository. The full project context is in
[CLAUDE.md](CLAUDE.md); read it first (architecture, commands, gotchas, conventions, decisions, open work), then
[HANDOFF.md](HANDOFF.md) for how to pick the project up.

Essentials:

- **Tasks:** run `make` to list them. `make typecheck` is the fast check (no permission reset); `make build` and
  `make install` rebuild the app; `make test` runs the pytest suite (typecheck first). Underneath: `cd app && swiftc -swift-version 5 -typecheck Sources/*.swift`. There is no Xcode project; the app is
  built with `swiftc` from the Command Line Tools (`app/build_app.sh`). Do not use SwiftUI `@State`.
- **Rebuilding resets macOS permissions** (ad-hoc signing). Batch changes and tell the maintainer when Accessibility and
  Screen Recording must be re-granted.
- **CI** runs `make test` and `make build` on macOS 14 and 15 (`.github/workflows/ci.yml`). Keep it green; pin any new
  action to a commit SHA.
- **Offline only.** No cloud services or telemetry. Dependencies stay hash-locked (`--require-hashes`); regenerate
  `THIRD_PARTY_NOTICES.md` when requirements change. GPL packages are never bundled.
- **Commits:** small and logical, imperative subject with a body that says why, repo-local git identity. Do not push,
  force-push, rewrite history or change repository visibility unless asked.
- **No real screenshots or absolute home paths** in committed files; the test image and demo are synthetic.
- Say plainly what was and was not tested; the maintainer verifies hotkeys, pickers and permission flows by hand.
