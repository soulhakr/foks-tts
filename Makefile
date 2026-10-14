# Developer tasks for FOKS TTS. Plain make (the 3.81 that ships with the Command Line Tools); nothing to install.
# Run `make` to list the tasks. End users run ./install.sh instead.
SHELL := /bin/zsh
.DEFAULT_GOAL := help

FOKS_HOME ?= $(HOME)/Library/Application Support/FOKS-TTS
PY        := $(FOKS_HOME)/venv/bin/python
APP       := app/build/FOKS TTS.app
DEV       := .venv-dev

.PHONY: help typecheck test build install check notices audit clean

help:  ## list the tasks
	@awk -F':.*## ' '/^[a-z-]+:.*## /{printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

typecheck:  ## fast Swift compile check (no build, no permission reset)
	cd app && swiftc -swift-version 5 -typecheck Sources/*.swift

# The test environment: hash-locked (requirements/dev.lock), project-local, rebuilt only when the lock changes.
$(DEV)/.installed: requirements/dev.lock
	UV_PYTHON_PREFERENCE=only-managed uv venv --clear --python 3.13 $(DEV)
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

audit:  ## print history matches for home paths, the OS username, personal email domains
	@git log -p --all | grep -n -i -E "/Users/|$$(whoami)|@(gmail|icloud|outlook|hotmail)\." | sort | uniq -c || true
	@git log --all --format='%an <%ae>' | sort -u

clean:  ## remove the build output and the test environment
	rm -rf app/build $(DEV)
