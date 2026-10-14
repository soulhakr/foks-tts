import numpy as np
import pytest


# ---- clean ---------------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("raw, expected", [
    ("72°F", "72 degrees"),
    ("45°", "45 degrees"),
    ("R&D", "R and D"),
    ("• item", "item"),
    ("a | b <c>", "a b c"),
    ("  lots   of\tspace ", "lots of space"),
    ("•", ""),
    ("", ""),
])
def test_clean(core, raw, expected):
    assert core.clean(raw) == expected


# ---- make_chunks ---------------------------------------------------------------------------------------------------

def words(n, ender_at=()):
    return [("w%d." % i) if i in ender_at else ("w%d" % i) for i in range(n)]


def test_chunks_cover_every_word_once_in_order(core):
    w = words(137, ender_at={20, 55, 90})
    chunks = core.make_chunks(list(range(len(w))), w)
    assert [i for c in chunks for i in c] == list(range(137))


def test_first_chunk_is_short_and_later_chunks_are_capped(core):
    w = words(200)
    chunks = core.make_chunks(list(range(200)), w)
    assert len(chunks[0]) == 14
    assert all(len(c) <= 40 for c in chunks[1:])


def test_sentence_end_splits_only_after_eight_words(core):
    w = ["a", "b.", "c", "d", "e", "f", "g", "h", "i."] + ["x"] * 3     # "b." is too early; "i." is word 9
    chunks = core.make_chunks(list(range(len(w))), w)
    assert chunks[0] == list(range(9))


def test_a_pause_forces_a_chunk_boundary(core):
    w = words(10)
    pauses = [0.0] * 10
    pauses[2] = 0.35
    chunks = core.make_chunks(list(range(10)), w, pauses=pauses)
    assert chunks[0] == [0, 1, 2]


def test_make_chunks_with_no_words(core):
    assert core.make_chunks([], []) == []


# ---- align ---------------------------------------------------------------------------------------------------------

def test_align_one_token_per_word(core):
    out = core.align([("Hello", 0.0, 0.5), ("world", 0.6, 1.0)], [0, 1], ["Hello", "world"])
    assert out == [(0, 0.0, 0.5), (1, 0.6, 1.0)]


def test_align_merges_tokens_that_split_a_word(core):
    toks = [("Hel", 0.0, 0.2), ("lo", 0.2, 0.5), ("world", 0.6, 1.0)]
    out = core.align(toks, [0, 1], ["Hello", "world"])
    assert out[0] == (0, 0.0, 0.5)
    assert out[1] == (1, 0.6, 1.0)


def test_align_skipped_word_does_not_shift_later_words(core):
    """An out-of-dictionary word has a token without timestamps. It must still consume its characters, or every
    later word would be matched to the wrong token."""
    toks = [("see", 0.0, 0.3), ("Xyzzy", None, None), ("now", 0.5, 0.8)]
    out = core.align(toks, [0, 1, 2], ["see", "Xyzzy", "now"])
    assert out[2] == (2, 0.5, 0.8)
    assert out[1] == (1, 0.3, 0.5)                     # the skipped word sits between its neighbours


def test_align_ignores_whitespace_in_tokens(core):
    """A whitespace-only token must consume nothing, or its length is taken out of the next word."""
    toks = [("Hello", 0.0, 0.5), (" ", None, None), ("world", 0.6, 1.0)]
    out = core.align(toks, [0, 1, 2], ["Hello", "world", "again"])
    assert out[1] == (1, 0.6, 1.0)
    assert out[2][1] == 1.0                            # "again" has no token: it starts where "world" ends


def test_align_spans_are_ordered_and_cover_all_indexes(core):
    cleaned = ["one", "two", "three", "four", "five"]
    toks = [("one", 0.0, 0.2), ("two", 0.3, 0.5), ("three", 0.6, 0.9), ("four", 1.0, 1.2), ("five", 1.3, 1.6)]
    out = core.align(toks, [0, 1, 2, 3, 4], cleaned)
    assert [i for i, _, _ in out] == [0, 1, 2, 3, 4]
    assert all(e >= s for _, s, e in out)
    assert all(out[k][1] <= out[k + 1][1] for k in range(len(out) - 1))


def test_align_with_a_subset_of_indexes(core):
    """Words that clean to nothing are left out of idx; the remaining indexes keep their original numbers."""
    cleaned = ["a", "", "b"]
    out = core.align([("a", 0.0, 0.1), ("b", 0.2, 0.3)], [0, 2], cleaned)
    assert [i for i, _, _ in out] == [0, 2]


def test_align_with_no_tokens_still_returns_every_word(core):
    out = core.align([], [0, 1], ["a", "b"])
    assert [i for i, _, _ in out] == [0, 1]


# ---- chunk_stream --------------------------------------------------------------------------------------------------

@pytest.fixture
def fake_synth(core, monkeypatch):
    calls = []

    def synth(idx, cleaned, voice, close=False):
        calls.append((list(idx), close))
        return np.ones(2400, dtype=np.float32), [(i, 0.0, 0.1) for i in idx]

    monkeypatch.setattr(core, "synth", synth)
    return calls


def test_chunk_stream_pads_the_silence_after_a_pause(core, fake_synth):
    w = ["Title", "body", "text"]
    chunks = list(core.chunk_stream(w, "af_heart", pauses=[0.35, 0.0, 0.0]))
    assert len(chunks) == 2
    assert len(chunks[0][0]) == 2400 + int(0.35 * core.SR)
    assert len(chunks[1][0]) == 2400
    assert fake_synth[0][1] is True                     # a section ending on a pause gets a falling ending
    assert fake_synth[1][1] is False


def test_chunk_stream_skips_words_that_clean_to_nothing(core, fake_synth):
    list(core.chunk_stream(["hello", "•", "world"], "af_heart"))
    assert fake_synth[0][0] == [0, 2]


def test_chunk_stream_stops_when_cancelled(core, fake_synth):
    w = ["a", "b"]
    out = list(core.chunk_stream(w, "af_heart", cancelled=lambda: True, pauses=[0.2, 0.0]))
    assert out == []


# ---- synth (fallback when a chunk fails) -----------------------------------------------------------------------------

class FakeResult:
    def __init__(self, n):
        self.output = type("O", (), {"audio": np.ones(n, dtype=np.float32)})()
        self.tokens = []


def test_synth_retries_a_failed_chunk_in_halves(core, monkeypatch):
    def pipe(text, voice):
        if " " in text:
            raise RuntimeError("broadcast_shapes")
        return [FakeResult(2400)]
    monkeypatch.setattr(core, "pipe_for", lambda voice: pipe)
    audio, spans = core.synth([0, 1, 2, 3], ["a", "b", "c", "d"], "af_heart")
    assert len(audio) == 4 * 2400
    assert [i for i, _, _ in spans] == [0, 1, 2, 3]
    assert all(spans[k][1] <= spans[k + 1][1] for k in range(3))     # shifted into order


def test_synth_gives_up_on_a_single_unreadable_word(core, monkeypatch, capsys):
    def pipe(text, voice):
        raise RuntimeError("no")
    monkeypatch.setattr(core, "pipe_for", lambda voice: pipe)
    audio, spans = core.synth([0], ["zzz"], "af_heart")
    assert len(audio) == 0 and spans == []
    assert "skipped unreadable word" in capsys.readouterr().err


# ---- upstream workarounds ------------------------------------------------------------------------------------------

def test_sinegen_patch_trims_the_extra_frame(core):
    from mlx_audio.tts.models.kokoro import istftnet
    f0 = np.zeros((1, 3000, 1))
    assert istftnet.SineGen()._f02sine(f0).shape == (1, 3000, 9)


def test_espeak_stand_in_is_registered_when_the_addon_is_absent(core):
    import sys
    assert core.HAS_ESPEAK is False
    with pytest.raises(RuntimeError):
        sys.modules["misaki.espeak"].EspeakG2P()
