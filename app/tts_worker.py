"""Resident Kokoro worker for the OfflineTTS menubar app.

Protocol: newline-delimited JSON on stdin/stdout. stdout carries ONLY protocol messages
(library prints are redirected to stderr).
  in : {"cmd":"speak","id":N,"words":[...],"voice":"af_heart","out_dir":"/tmp/x"}
       {"cmd":"cancel","id":N}
  out: {"ready":true}
       {"id":N,"chunk":k,"wav":path,"dur":sec,"spans":[{"i":wordIndex,"start":s,"end":e}]}
       {"id":N,"final":true} | {"id":N,"cancelled":true} | {"id":N,"error":"..."}
"""
import json, os, queue, sys, threading
os.environ.setdefault("HF_HUB_OFFLINE", "1")
proto = sys.stdout
sys.stdout = sys.stderr
_here = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [_here, os.path.dirname(_here)]  # bundle Resources, or repo root in dev
import numpy as np
from scipy.io import wavfile
import tts_core as core

jobs = queue.Queue()
cancelled = set()


def send(obj):
    proto.write(json.dumps(obj) + "\n")
    proto.flush()


def reader():
    for line in sys.stdin:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("cmd") == "cancel":
            cancelled.add(msg.get("id"))
        elif msg.get("cmd") == "speak":
            jobs.put(msg)
    jobs.put(None)  # stdin closed: parent is gone


def run(job):
    jid, voice = job["id"], job.get("voice", "af_heart")
    os.makedirs(job["out_dir"], exist_ok=True)
    try:
        for k, (a, spans) in enumerate(core.chunk_stream(job["words"], voice, lambda: jid in cancelled)):
            path = os.path.join(job["out_dir"], f"chunk_{k}.wav")
            wavfile.write(path, core.SR, (np.clip(a, -1, 1) * 32767).astype(np.int16))
            send({"id": jid, "chunk": k, "wav": path, "dur": len(a) / core.SR,
                  "spans": [{"i": i, "start": s, "end": e} for i, s, e in spans]})
        send({"id": jid, "cancelled": True} if jid in cancelled else {"id": jid, "final": True})
    except Exception as e:  # noqa
        send({"id": jid, "error": str(e)})


def main():
    core.pipe_for("af_heart")  # load model + American pipeline up front
    threading.Thread(target=reader, daemon=True).start()
    send({"ready": True})
    while True:
        job = jobs.get()
        if job is None:
            break
        run(job)


main()
