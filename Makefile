# Developer tasks for FOKS TTS. Plain make (the 3.81 that ships with the Command Line Tools); nothing to install.
# Run `make` to list the tasks. End users run ./install.sh instead.
SHELL := /bin/zsh
.DEFAULT_GOAL := help

FOKS_HOME ?= $(HOME)/Library/Application Support/FOKS-TTS
PY        := $(FOKS_HOME)/venv/bin/python
APP       := app/build/FOKS TTS.app
DEV       := .venv-dev
PLIST     := app/Info.plist
SEMVER    := ^[0-9]+\.[0-9]+\.[0-9]+$$

.PHONY: help typecheck test build install check notices screenshots audit bump release clean

help:  ## list the tasks
	@awk -F':.*## ' '/^[a-z-]+:.*## /{printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

typecheck:  ## fast Swift compile check (no build, no permission reset)
	cd app && swiftc -swift-version 5 -typecheck Sources/*.swift

# The test environment: hash-locked (requirements/dev.lock), project-local, rebuilt only when the lock changes.
$(DEV)/.installed: requirements/dev.lock
	UV_PYTHON_PREFERENCE=only-managed uv venv --clear --python 3.14 $(DEV)
	uv pip install --python $(DEV)/bin/python --require-hashes --no-deps -r requirements/dev.lock
	@touch $@

test: typecheck $(DEV)/.installed  ## typecheck, then pytest in the hash-locked .venv-dev (Structure test also needs a build)
	$(DEV)/bin/python -m pytest -q

build:  ## build and ad-hoc sign "FOKS TTS.app" (macOS will ask for permissions again)
	cd app && ./build_app.sh

install: build  ## build, copy to ~/Applications, register the Services entry
	cd app && ./install_local.sh

check:  ## headless offline check of OCR, structure, audio and highlight (uses the existing build)
	@test -d "$(APP)" || { echo "no build found: run 'make build' first"; exit 1; }
	sandbox-exec -p '(version 1)(allow default)(deny network*)' \
	  "$(APP)/Contents/MacOS/FOKS-TTS" --read-image test_screenshot.png --snapshots "$${TMPDIR}frames" --at 0.5,2,4

notices:  ## regenerate THIRD_PARTY_NOTICES.md from the installed packages
	"$(PY)" tools/gen_notices.py

screenshots:  ## re-render the README images in docs/ (Settings light and dark, menu bar icon)
	tools/render_screenshots.sh

audit:  ## print history matches for home paths, the OS username, personal email domains
	@git log -p --all | grep -n -i -E "/Users/|$$(whoami)|@(gmail|icloud|outlook|hotmail)\." | sort | uniq -c || true
	@git log --all --format='%an <%ae>' | sort -u

bump:  ## set the version in app/Info.plist and add 1 to the build number: make bump VERSION=0.1.0 (then commit it)
	@test -n "$(VERSION)" || { echo "usage: make bump VERSION=0.1.0"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '$(SEMVER)' || { echo "VERSION must be MAJOR.MINOR.PATCH, like 0.1.0"; exit 1; }
	@build=$$(plutil -extract CFBundleVersion raw -o - $(PLIST)); \
	  sed -E -i '' -e "s#(<key>CFBundleShortVersionString</key><string>)[^<]*(</string>)#\1$(VERSION)\2#" \
	    -e "s#(<key>CFBundleVersion</key><string>)[^<]*(</string>)#\1$$((build + 1))\2#" $(PLIST)
	@git diff -U0 $(PLIST) | grep -E '^[-+] '; echo "Add a CHANGELOG.md entry for $(VERSION), commit, push, then: make release VERSION=$(VERSION)"

release:  ## source release: make release VERSION=0.1.0 (checks, all tests incl. the built-app one, tarball + checksum in dist/, local tag; publishes nothing)
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.1"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '$(SEMVER)' || { echo "VERSION must be MAJOR.MINOR.PATCH, like 0.1.0"; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = main || { echo "release from main"; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "the working tree is not clean: commit or stash first"; exit 1; }
	@test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" || { echo "HEAD differs from origin/main: push or pull first"; exit 1; }
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then echo "tag v$(VERSION) already exists"; exit 1; fi
	@plist=$$(plutil -extract CFBundleShortVersionString raw -o - $(PLIST)); \
	  test "$$plist" = "$(VERSION)" || { echo "$(PLIST) says $$plist: run 'make bump VERSION=$(VERSION)', commit and push"; exit 1; }
	@grep -q '^## \[$(VERSION)\]' CHANGELOG.md || { echo "CHANGELOG.md has no '## [$(VERSION)]' entry: add one and commit"; exit 1; }
	@new=$$(plutil -extract CFBundleVersion raw -o - $(PLIST)); prev=$$(git tag --list 'v*' --sort=-v:refname | head -1); \
	  echo "$$new" | grep -Eq '^[0-9]+$$' || { echo "CFBundleVersion must be a whole number, is '$$new'"; exit 1; }; \
	  if [ -n "$$prev" ]; then old=$$(git show "$${prev}:$(PLIST)" | plutil -extract CFBundleVersion raw -o - -); \
	    test "$$new" -gt "$$old" || { echo "build number $$new must be greater than $$old (in $$prev): run 'make bump'"; exit 1; }; fi
	@bad=$$(git log --all --format=%ae | sort -u | grep -v '@users.noreply.github.com$$' || true); \
	  test -z "$$bad" || { echo "history has author emails other than the GitHub noreply address: $$bad"; exit 1; }
	@test -d "$(APP)" || { echo "no build found: run 'make build' first (a release runs the headless Structure test against it)"; exit 1; }
	@stale=$$(find app/Sources app/tts_worker.py tts_core.py app/Info.plist -type f -newer "$(APP)/Contents/MacOS/FOKS-TTS"); \
	  test -z "$$stale" || { echo "the build is older than these files: run 'make build' again"; echo "$$stale"; exit 1; }
	FOKS_REQUIRE_INTEGRATION=1 $(MAKE) test
	$(MAKE) notices
	@git diff --quiet THIRD_PARTY_NOTICES.md || { echo "THIRD_PARTY_NOTICES.md was out of date and has been regenerated: commit it and re-run"; exit 1; }
	mkdir -p dist
	git archive --format=tar.gz --prefix=foks-tts-$(VERSION)/ -o dist/foks-tts-$(VERSION).tar.gz HEAD
	cd dist && shasum -a 256 foks-tts-$(VERSION).tar.gz > foks-tts-$(VERSION).tar.gz.sha256
	git tag -a v$(VERSION) -m "FOKS TTS $(VERSION)"
	@echo; echo "Built dist/foks-tts-$(VERSION).tar.gz (+ .sha256) and created the local tag v$(VERSION). Nothing was published."
	@echo "To publish: git push origin v$(VERSION), then create a release from the tag and attach the files in dist/."

clean:  ## remove the build output, the test environment and dist/
	rm -rf app/build $(DEV) dist
