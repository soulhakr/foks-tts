"""Shared Kokoro helpers: text cleanup, chunking, token->word alignment, chunked synthesis.

Used by speak_words.py (one-shot CLI) and app/tts_worker.py (resident worker for the menubar app).
Works around an input-dependent mlx-audio 0.4.4 'broadcast_shapes' failure by retrying a failed
chunk in two halves.
"""
import os, re, sys
os.environ.setdefault("HF_HUB_OFFLINE", "1")
import numpy as np
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

REPO = "mlx-community/Kokoro-82M-bf16"
VOICE_DIR = os.path.expanduser("~/AI/kokoro/voices")
SR = 24000
_model = None
_pipes = {}


def voice_path(voice):
    return os.path.join(VOICE_DIR, voice + ".safetensors")


def pipe_for(voice):
    """British voices (b*) need lang_code 'b'; everything else we offer is American."""
    global _model
    if _model is None:
        _model = load_model(REPO)
    lang = "b" if voice.startswith("b") else "a"
    if lang not in _pipes:
        _pipes[lang] = KokoroPipeline(lang_code=lang, model=_model, repo_id=REPO)
    return _pipes[lang]


def clean(w):
    t = w.replace("°F", " degrees").replace("°", " degrees").replace("&", " and ")
    t = re.sub(r"[<>|•]+", "", t)
    return re.sub(r"\s+", " ", t).strip()


def make_chunks(idx, words, first_max=14, hard_max=40):
    """Group word indexes into sentence-ish chunks; a short first chunk gets audio out fast."""
    out, cur = [], []
    for i in idx:
        cur.append(i)
        limit = first_max if not out else hard_max
        if (re.search(r"[.!?:;]$", words[i]) and len(cur) >= 8) or len(cur) >= limit:
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


def synth(idx, cleaned, voice):
    text = " ".join(cleaned[i] for i in idx)
    try:
        audio, toks, off = [], [], 0.0
        for r in pipe_for(voice)(text, voice=voice_path(voice)):
            a = np.asarray(r.output.audio).reshape(-1)
            for t in getattr(r, "tokens", None) or []:
                if t.start_ts is not None and t.end_ts is not None:
                    toks.append((t.text, t.start_ts + off, t.end_ts + off))
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
        a2, s2 = synth(idx[h:], cleaned, voice)
        shift = len(a1) / SR
        return np.concatenate([a1, a2]), s1 + [(i, s + shift, e + shift) for i, s, e in s2]


def chunk_stream(words, voice, cancelled=lambda: False):
    """Yield (audio float32 array, [(word_index, start, end)]) per chunk; spans are chunk-relative."""
    cleaned = [clean(w) for w in words]
    idx = [i for i, c in enumerate(cleaned) if c]
    for ch in make_chunks(idx, words):
        if cancelled():
            return
        a, spans = synth(ch, cleaned, voice)
        if len(a):
            yield a, spans
