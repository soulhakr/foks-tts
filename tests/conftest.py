"""Test setup. tts_core imports MLX and mlx-audio at module level, so the unit tests replace them with small stand-ins
before importing it. That keeps them fast, offline and runnable with just numpy and pytest (no model, no GPU)."""
import os
import sys
import types

import numpy as np
import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)


class FakeSineGen:
    """Stands in for mlx-audio's SineGen: _f02sine returns one extra 300-sample frame, as in the real bug."""
    def _f02sine(self, f0_values):
        n = f0_values.shape[1]
        return np.zeros((f0_values.shape[0], n + 300, 9))


def _module(name, **attrs):
    mod = types.ModuleType(name)
    mod.__dict__.update(attrs)
    sys.modules[name] = mod
    return mod


def _install_stubs():
    _module("mlx")
    _module("mlx.core")
    sys.modules["mlx"].core = sys.modules["mlx.core"]
    _module("mlx_audio")
    _module("mlx_audio.tts")
    _module("mlx_audio.tts.utils", load_model=lambda *a, **k: object())
    _module("mlx_audio.tts.models")
    _module("mlx_audio.tts.models.kokoro")
    _module("mlx_audio.tts.models.kokoro.pipeline", KokoroPipeline=object)
    istftnet = _module("mlx_audio.tts.models.kokoro.istftnet", SineGen=FakeSineGen)
    sys.modules["mlx_audio.tts.models.kokoro"].istftnet = istftnet
    _module("misaki")  # not a package, so `import misaki.espeak` fails like it does without the GPL add-on


_install_stubs()
sys.modules.pop("tts_core", None)
import tts_core  # noqa: E402


@pytest.fixture(scope="session")
def core():
    return tts_core
