"""Structure (title / body / control detection and pauses) is Swift, so it is tested through the built app's headless
mode: it OCRs test_screenshot.png, synthesizes the speech and prints one STRUCT line per pause. Needs `make build`,
the FOKS venv and the Kokoro model; skipped otherwise."""
import os
import re
import shutil
import subprocess
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app/build/FOKS TTS.app/Contents/MacOS/FOKS-TTS")
IMAGE = os.path.join(ROOT, "test_screenshot.png")

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(sys.platform != "darwin", reason="macOS only"),
    pytest.mark.skipif(not os.path.exists(APP), reason="app not built: run `make build`"),
]


@pytest.fixture(scope="module")
def struct_lines(tmp_path_factory):
    frames = tmp_path_factory.mktemp("frames")
    cmd = [APP, "--read-image", IMAGE, "--snapshots", str(frames), "--at", "0.5"]
    if shutil.which("sandbox-exec"):                       # prove it works with the network denied
        cmd = ["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    return [line for line in p.stderr.splitlines() if line.startswith("STRUCT")]


def test_title_body_and_controls_are_told_apart(struct_lines):
    summary = next(l for l in struct_lines if "kinds in order" in l)
    assert '["title", "body", "ui"]' in summary


def test_a_pause_follows_the_title_and_the_kind_change(struct_lines):
    pauses = [(m.group(1), float(m.group(2)), float(m.group(3)))
              for l in struct_lines
              for m in [re.match(r"STRUCT \S+\s+(\w+)\s+pause set ([\d.]+)s, audible gap ([\d.]+)s", l)] if m]
    kinds = [k for k, _, _ in pauses]
    assert kinds[:2] == ["title", "body"]
    assert pauses[0][1] == pytest.approx(0.35)             # after the title
    assert pauses[1][1] == pytest.approx(0.30)             # body -> controls
    assert all(gap >= setp for _, setp, gap in pauses)     # the audible silence is at least what was asked for
