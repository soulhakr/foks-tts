"""Offline Kokoro speech with chunking + retry-by-splitting (works around an mlx-audio 0.4.4
Kokoro 'broadcast_shapes' failure that is input-dependent). Usage: speak.py out.wav < text"""
import os, re, sys
os.environ.setdefault("HF_HUB_OFFLINE", "1")
import numpy as np
from scipy.io import wavfile
from mlx_audio.tts.utils import load_model

VOICE = os.path.expanduser("~/AI/kokoro/voices/af_heart.safetensors")
MAX_CHARS = 200
model = load_model("mlx-community/Kokoro-82M-bf16")

def clean(t):
    t = t.replace("°F", " degrees").replace("°", " degrees").replace("&", " and ")
    t = re.sub(r"\s*[>|•]\s*", ", ", t)
    return re.sub(r"[ \t]+", " ", t).strip()

def pack(text):
    parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+|\n+", text) if p.strip()]
    chunks, cur = [], ""
    for p in parts:
        if cur and len(cur) + 1 + len(p) > MAX_CHARS:
            chunks.append(cur); cur = p
        else:
            cur = f"{cur} {p}".strip()
    return chunks + ([cur] if cur else [])

def synth(t, depth=0):
    try:
        return [np.asarray(r.audio) for r in model.generate(text=t, voice=VOICE, lang_code="a")]
    except Exception as e:
        words = t.split()
        if len(words) < 2:
            print(f"skipped unreadable token: {t!r}", file=sys.stderr); return []
        h = len(words) // 2
        return synth(" ".join(words[:h]), depth + 1) + synth(" ".join(words[h:]), depth + 1)

text = clean(sys.stdin.read())
audio = []
for c in pack(text):
    audio += synth(c)
if not audio:
    sys.exit("no audio produced")
wavfile.write(sys.argv[1], 24000, (np.concatenate(audio) * 32767).astype(np.int16))
print(f"wrote {sys.argv[1]} ({sum(len(a) for a in audio)/24000:.1f}s)")
