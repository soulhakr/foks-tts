"""One-shot offline Kokoro speech with per-word timing (used by read_screen.swift).

Usage: speak_words.py words.json out.wav timeline.json [voice]
"""
import json, sys
import numpy as np
from scipy.io import wavfile
import tts_core as core


def main():
    words = [w["text"] for w in json.load(open(sys.argv[1]))["words"]]
    voice = sys.argv[4] if len(sys.argv) > 4 else "af_heart"
    audio, timeline, off = [], [], 0.0
    for a, spans in core.chunk_stream(words, voice):
        timeline += [{"i": i, "start": s + off, "end": e + off} for i, s, e in spans]
        audio.append(a)
        off += len(a) / core.SR
    if not audio:
        sys.exit("no audio produced")
    wavfile.write(sys.argv[2], core.SR, (np.clip(np.concatenate(audio), -1, 1) * 32767).astype(np.int16))
    json.dump(timeline, open(sys.argv[3], "w"))
    print(f"wrote {sys.argv[2]} ({off:.1f}s, {len(timeline)} words)", file=sys.stderr)


main()
