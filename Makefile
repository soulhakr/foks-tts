# Developer tasks for FOKS TTS. Plain make (the 3.81 that ships with the Command Line Tools); nothing to install.
# Run `make` to list the tasks. End users run ./install.sh instead.
SHELL := /bin/zsh
.DEFAULT_GOAL := help

FOKS_HOME ?= $(HOME)/Library/Application Support/FOKS-TTS
PY        := $(FOKS_HOME)/venv/bin/python
APP       := app/build/FOKS TTS.app

.PHONY: help typecheck test build install check notices audit clean

help:  ## list the tasks
	@awk -F':.*## ' '/^[a-z-]+:.*## /{printf "  make %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

typecheck:  ## fast Swift compile check (no build, no permission reset)
	cd app && swiftc -swift-version 5 -typecheck Sources/*.swift

test: typecheck  ## typecheck, then pytest (unit tests; the Structure test also needs a build)
	uv run --no-project --python 3.13 --with 'pytest>=8' --with numpy==2.5.1 pytest -q

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

clean:  ## remove the build output
	rm -rf app/build
