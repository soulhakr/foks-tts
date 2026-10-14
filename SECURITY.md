# Security policy

FOKS TTS is a personal project maintained on a best-effort basis. There is no service level agreement, but security
reports are taken seriously and read first.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Report it privately through GitHub:

**[Report a vulnerability](https://github.com/soulhakr/foks-tts/security/advisories/new)** (the *Security* tab, then
*Report a vulnerability*).

Include what you found, the version (*Settings > About*, or the `launch` line in `~/Library/Logs/FOKS-TTS/foks.log`), your
macOS version, and steps to reproduce. Please do not attach screenshots or logs that contain content you would not want
shared; the app's own log never contains the text it reads, so it is safe to attach.

I will try to acknowledge a report promptly and follow up with a fix or a clear explanation. If you would like to be
credited in the changelog, say so in the report.

## Supported versions

Only the latest release receives fixes (the project is at `0.x`; see [CHANGELOG.md](CHANGELOG.md)).

## What counts as a security issue here

FOKS TTS reads text from other apps, so its promises are about **privacy and permissions**. These are in scope:

- **Anything that sends data off the Mac at run time.** After installation the app and its voice engine are meant to make
  no network connections: no telemetry, no cloud service, no update check. A connection you can observe is a bug.
- **Screen or app text leaving the app's own memory and temporary files**, for example text written to the log (the log
  is meant to hold events, counts and timings only), or audio and word files left in the temporary folder after a read.
- **Misuse of the Accessibility or Screen Recording permissions**, or reading from windows or selections the user did not
  point at.
- **The installer and its supply chain:** `install.sh` installs from hash-locked requirements
  (`pip --require-hashes`) and checks the Kokoro model's SHA-256. A way to make it install something else is in scope.
- **The worker process:** the Python voice worker is started by the app and talks to it over standard input and output.
  Ways to make it run unintended code or read unintended files are in scope.

Out of scope: reports that need an attacker who already controls your account or the machine, issues in the
third-party packages themselves (report those upstream; hashes pin the versions we ship), and the Accessibility and
Screen Recording prompts themselves, which are macOS behavior.

## Design notes that may help a review

- The app is unsandboxed and not distributed through the Mac App Store, because reading other apps requires
  Accessibility and a spawned Python process. It is built locally from source (`./install.sh`) and ad-hoc signed.
- Network access is used only by `install.sh` (PyPI, GitHub for the Python build and spaCy model, Hugging Face for the
  model). The headless test mode can be run under `sandbox-exec` with network access denied (see `CLAUDE.md`).
- GPL-licensed pronunciation packages are an optional add-on installed on request and never bundled.
