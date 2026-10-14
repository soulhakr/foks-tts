"""The dependency lock files must stay hash-locked and in step with their source lists.
Cheap checks that need no network: every locked package carries SHA-256 hashes, every package named in a
requirements/*.txt is locked (at the same version when the .txt pins one), and the locks hold nothing unexplained."""
import os
import re

import pytest

REQ = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "requirements")
PAIRS = [("core.txt", "core.lock"), ("optional-gpl-pronunciation.txt", "optional-gpl-pronunciation.lock"), ("dev.txt", "dev.lock")]
ENTRY = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_.\-]*)\s*(==\s*([^\s\;]+)|@\s*\S+|>=\s*\S+)?")


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def parse(path, locked):
    """-> {name: (version or None, [hashes])}. In a lock, an entry is a line at column 0 followed by --hash lines."""
    out, current = {}, None
    for line in open(path):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0] not in " \t":
            m = ENTRY.match(line.strip())
            assert m, f"unparsable line in {path}: {line!r}"
            current = norm(m.group(1))
            out[current] = (m.group(3), [])
        elif locked and "--hash=sha256:" in line and current:
            out[current][1].append(re.search(r"--hash=sha256:([0-9a-f]{64})", line).group(1))
    return out


@pytest.mark.parametrize("txt, lock", PAIRS)
def test_every_locked_package_has_sha256_hashes(txt, lock):
    entries = parse(os.path.join(REQ, lock), locked=True)
    assert entries, f"{lock} is empty"
    missing = [n for n, (_, hashes) in entries.items() if not hashes]
    assert not missing, f"{lock}: no hashes for {missing}"


@pytest.mark.parametrize("txt, lock", PAIRS)
def test_lock_covers_the_source_list(txt, lock):
    want = parse(os.path.join(REQ, txt), locked=False)
    have = parse(os.path.join(REQ, lock), locked=True)
    absent = sorted(set(want) - set(have))
    assert not absent, f"{txt} names packages that {lock} does not lock: {absent}"
    drift = {n: (v, have[n][0]) for n, (v, _) in want.items() if v and have[n][0] and v != have[n][0]}
    assert not drift, f"{txt} and {lock} pin different versions: {drift}"


def test_default_lock_has_no_gpl_packages():
    """The GPL pair is only ever the optional add-on (see README, 'Optional pronunciation add-on')."""
    core = parse(os.path.join(REQ, "core.lock"), locked=True)
    assert not {"phonemizer-fork", "espeakng-loader"} & set(core)


def test_lock_files_have_no_absolute_home_paths():
    for lock in [l for _, l in PAIRS]:
        text = open(os.path.join(REQ, lock)).read()
        assert "/Users/" not in text and "/home/" not in text, f"{lock} leaks a home path"
