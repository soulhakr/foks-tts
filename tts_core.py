"""Shared Kokoro helpers: text cleanup, chunking, token->word alignment, chunked synthesis.

Used by app/tts_worker.py (the resident worker for the menubar app) and by the unit tests in tests/.
Works around an input-dependent mlx-audio 0.4.4 'broadcast_shapes' failure by retrying a failed
chunk in two halves.
"""
import os, re, sys, types
os.environ.setdefault("HF_HUB_OFFLINE", "1")
import numpy as np
import mlx.core as mx
from mlx_audio.tts.utils import load_model
from mlx_audio.tts.models.kokoro.pipeline import KokoroPipeline


def _patch_sinegen():
    """Fix for mlx-audio 0.4.4: SineGen._f02sine resamples f0 down by 300 then back up; when the
    f0 length is an exact multiple of 300, float rounding yields one extra 300-sample frame, so
    sine_waves (N+300) no longer broadcasts against the uv/noise arrays (N). That is the
    '[broadcast_shapes] Shapes (1,N,1) and (1,N+300,9)' failure. Trim to the f0 length."""
    from mlx_audio.tts.models.kokoro import istftnet
    cls = next(c for c in vars(istftnet).values() if isinstance(c, type) and hasattr(c, "_f02sine"))
    orig = cls._f02sine
    def trimmed(self, f0_values):
        return orig(self, f0_values)[:, : f0_values.shape[1], :]
    cls._f02sine = trimmed


_patch_sinegen()


def _setup_espeak():
    """eSpeak NG is an OPTIONAL, separately installed pronunciation fallback (GPL-licensed packages
    phonemizer-fork + espeakng-loader). mlx-audio 0.4.4 imports misaki.espeak unconditionally, so when
    the optional packages are absent we register a tiny stand-in module whose constructors raise; that
    makes mlx-audio fall back to "OOD words will be skipped" instead of failing to start."""
    try:
        import misaki.espeak  # noqa: F401  (real module: needs the optional packages)
        return True
    except Exception:
        stub = types.ModuleType("misaki.espeak")

        class EspeakFallback:
            def __init__(self, *a, **k):
                raise RuntimeError("optional eSpeak NG pronunciation fallback is not installed")

        class EspeakG2P(EspeakFallback):
            pass

        stub.EspeakFallback, stub.EspeakG2P = EspeakFallback, EspeakG2P
        sys.modules["misaki.espeak"] = stub
        import misaki
        misaki.espeak = stub
        return False


HAS_ESPEAK = _setup_espeak()

REPO = "mlx-community/Kokoro-82M-bf16"
FOKS_HOME = os.environ.get("FOKS_TTS_HOME") or os.path.expanduser("~/Library/Application Support/FOKS-TTS")
MODEL_DIR = os.environ.get("FOKS_TTS_MODEL_DIR") or os.path.join(FOKS_HOME, "models", "kokoro")  # install.sh populates the default; the app can override
VOICE_DIR = os.path.join(MODEL_DIR, "voices")
SR = 24000
_model = None
_pipes = {}


def voice_path(voice):
    return os.path.join(VOICE_DIR, voice + ".safetensors")


def pipe_for(voice):
    """British voices (b*) need lang_code 'b'; everything else we offer is American."""
    global _model
    if _model is None:
        # Prefer the model folder installed by install.sh; fall back to the Hugging Face cache (developer setups).
        _model = load_model(MODEL_DIR if os.path.isfile(os.path.join(MODEL_DIR, "config.json")) else REPO)
    lang = "b" if voice.startswith("b") else "a"
    if lang not in _pipes:
        _pipes[lang] = KokoroPipeline(lang_code=lang, model=_model, repo_id=REPO)
    return _pipes[lang]


def clean(w):
    t = w.replace("°F", " degrees").replace("°", " degrees").replace("&", " and ")
    t = re.sub(r"[<>|•]+", "", t)
    return re.sub(r"\s+", " ", t).strip()


def make_chunks(idx, words, pauses=None, first_max=14, hard_max=40):
    """Group word indexes into sentence-ish chunks; a short first chunk gets audio out fast. A word followed by a
    pause always ends its chunk, so the silence goes between sections (title / body / controls)."""
    out, cur = [], []
    for i in idx:
        cur.append(i)
        limit = first_max if not out else hard_max
        forced = pauses is not None and pauses[i] > 0
        if forced or (re.search(r"[.!?:;]$", words[i]) and len(cur) >= 8) or len(cur) >= limit:
            out.append(cur)
            cur = []
    return out + ([cur] if cur else [])


def align(toks, idx, cleaned):
    """toks: [(text, start, end)] -> [(word_index, start, end)] for every word in idx."""
    rem = [cleaned[i].replace(" ", "") for i in idx]
    spans, k, pos = {}, 0, 0
    for text, s, e in toks:
        n = len(text.replace(" ", ""))
        while n > 0 and k < len(idx):
            take = min(n, len(rem[k]) - pos)
            if s is not None:
                sp = spans.setdefault(idx[k], [s, e])
                sp[1] = e
            pos += take
            n -= take
            if pos >= len(rem[k]):
                k, pos = k + 1, 0
    out, prev_end = [], 0.0
    for n_, i in enumerate(idx):
        if i in spans:
            s, e = spans[i]
        else:  # no token matched: sit between neighbours
            nxt = next((spans[j][0] for j in idx[n_ + 1:] if j in spans), prev_end + 0.2)
            s, e = prev_end, max(prev_end, nxt)
        out.append((i, s, max(e, s)))
        prev_end = max(prev_end, e)
    return out


def synth(idx, cleaned, voice, close=False):
    text = " ".join(cleaned[i] for i in idx)
    if close and not re.search(r"[.!?,;:]$", text):
        text += "."          # a section that ends without punctuation (a title, a button label) still gets a falling ending
    try:
        audio, toks, off = [], [], 0.0
        for r in pipe_for(voice)(text, voice=voice_path(voice)):
            a = np.asarray(r.output.audio).reshape(-1)
            for t in getattr(r, "tokens", None) or []:
                # keep tokens without timestamps (e.g. skipped out-of-dictionary words): their characters
                # must still be consumed or every later word would be matched to the wrong token
                has = t.start_ts is not None and t.end_ts is not None
                toks.append((t.text, t.start_ts + off if has else None, t.end_ts + off if has else None))
            audio.append(a)
            off += len(a) / SR
        if not audio:
            raise RuntimeError("no audio")
        return np.concatenate(audio), align(toks, idx, cleaned)
    except Exception:
        if len(idx) < 2:
            print(f"skipped unreadable word: {text!r}", file=sys.stderr)
            return np.zeros(0, dtype=np.float32), []
        h = len(idx) // 2
        a1, s1 = synth(idx[:h], cleaned, voice)
        a2, s2 = synth(idx[h:], cleaned, voice, close)
        shift = len(a1) / SR
        return np.concatenate([a1, a2]), s1 + [(i, s + shift, e + shift) for i, s, e in s2]


def chunk_stream(words, voice, cancelled=lambda: False, pauses=None):
    """Yield (audio float32 array, [(word_index, start, end)]) per chunk; spans are chunk-relative.
    `pauses[i]` is seconds of silence to add after word i (the chunk is padded with it)."""
    cleaned = [clean(w) for w in words]
    idx = [i for i, c in enumerate(cleaned) if c]
    for ch in make_chunks(idx, words, pauses):
        if cancelled():
            return
        pause = pauses[ch[-1]] if pauses else 0
        a, spans = synth(ch, cleaned, voice, close=pause > 0)
        if len(a):
            if pause > 0:
                a = np.concatenate([a, np.zeros(int(pause * SR), dtype=a.dtype)])
            yield a, spans
