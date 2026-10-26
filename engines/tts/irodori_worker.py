#!/usr/bin/env python3
"""Offline, persistent Irodori/MLX JSON-lines worker (no network or playback).

Start with --model /local/model --output-dir /private/job/directory.
The first JSON line is {ready:true,...}. Requests contain id, text, voice,
instructions and optionally output (a new .wav under output-dir). Replies
contain id, ok, output, duration_seconds and timing/memory information.
Only the three configured synthetic presets are accepted. Their fixed reference
utterances are cached per model revision/preset in output-dir/references.
"""
import argparse
import contextlib
import hashlib
import json
import math
import os
import signal
from pathlib import Path
import sys
import tempfile
import time

PRESETS = {
    "IrodoriAkari": "明るく自然な女性の声。親しみやすく、はっきりと日本語を話す。",
    "IrodoriAoi": "落ち着いた自然な男性の声。穏やかで、はっきりと日本語を話す。",
    "IrodoriNagi": "柔らかく自然な中性的な声。穏やかで、はっきりと日本語を話す。",
}
REFERENCE_TEXT = "こんにちは。今日はいい天気ですね。ゆっくりお話ししましょう。"
MAX_LINE = 16384
MAX_TEXT = 240


def emit(value):
    print(json.dumps(value, ensure_ascii=False, allow_nan=False), flush=True)


class Cancelled(BaseException):
    """Not swallowed by third-party ``except Exception`` error recovery."""


class Cancellation:
    def __init__(self, root):
        self.root = root
        self.marker = None
        self.active = False

    def begin(self, request_id):
        key = hashlib.sha256(str(request_id).encode()).hexdigest()
        self.marker = self.root / (".cancel-" + key)
        self.active = True
        # A cancel signal may have arrived while idle, before request dispatch.
        self.check()

    def check(self, signum=None, frame=None):
        if self.active and self.marker is not None and self.marker.exists():
            # Disarm before unwinding so repeated signals cannot interrupt cleanup.
            self.active = False
            raise Cancelled()

    def finish(self):
        self.active = False
        if self.marker is not None:
            self.marker.unlink(missing_ok=True)
            self.marker = None


def parse_request(line, root):
    value = json.loads(line)
    if not isinstance(value, dict):
        raise ValueError("request must be an object")
    request_id = value.get("id")
    if not isinstance(request_id, (str, int)) or isinstance(request_id, bool) or len(str(request_id)) > 100:
        raise ValueError("id must be a short string or integer")
    text = value.get("text")
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT:
        raise ValueError(f"text must contain 1..{MAX_TEXT} characters; split longer utterances")
    if any(ord(char) < 32 and char not in "\n\t" for char in text):
        raise ValueError("control characters in text")
    voice = value.get("voice", "IrodoriAkari")
    if voice not in PRESETS:
        raise ValueError("unknown voice preset")
    instructions = value.get("instructions", "")
    if not isinstance(instructions, str) or len(instructions) > 1000:
        raise ValueError("instructions must be a string of at most 1000 characters")
    # Rate/pitch are postprocessed by the host, never silently ignored here.
    speed = value.get("speed", 1.0)
    if isinstance(speed, bool) or not isinstance(speed, (int, float)) or not math.isfinite(speed) or speed != 1:
        raise ValueError("worker speed must be 1; host owns playback rate/pitch")
    output = value.get("output")
    if output is None:
        output = root / (hashlib.sha256(os.urandom(32)).hexdigest() + ".wav")
    elif not isinstance(output, str):
        raise ValueError("output must be a path string")
    output = Path(output).expanduser()
    if not output.is_absolute():
        output = root / output
    output = output.resolve()
    if root not in output.parents or output.suffix.lower() != ".wav":
        raise ValueError("output must be a .wav inside output-dir")
    if output.exists() or not output.parent.is_dir() or root / "references" in output.parents:
        raise ValueError("output already exists, parent is missing, or reference directory is reserved")
    return request_id, text.strip(), voice, instructions.strip(), output


class Worker:
    def __init__(self, model_path, output_dir):
        # Always require a complete local snapshot. Loading must never download.
        self.model_path = Path(model_path).resolve(strict=True)
        self.root = Path(output_dir).resolve(strict=True)
        if not self.root.is_dir():
            raise ValueError("output-dir must be an existing directory")
        for name in ("config.json", "model.safetensors", "dacvae/config.json", "dacvae/model.safetensors", "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json"):
            if not (self.model_path / name).is_file():
                raise ValueError("incomplete local model snapshot: " + name)
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
        # Third-party diagnostics are redirected away from the JSON channel.
        import mlx.core as mx
        import numpy as np
        import soundfile as sf
        from mlx_audio.tts.utils import load_model
        self.mx, self.np, self.sf = mx, np, sf
        self.model = load_model(self.model_path)
        if self.model.dacvae is None:
            raise RuntimeError("DACVAE failed to load")
        self.references = self.root / "references"
        self.references.mkdir(mode=0o700, exist_ok=True)
        if self.references.is_symlink():
            raise ValueError("reference directory must not be a symlink")
        # Include model identity and config in cache key, never reuse another model's voice.
        fingerprint = str(self.model_path) + (self.model_path / "config.json").read_text()
        weights = self.model_path / "model.safetensors"
        fingerprint += f":{weights.stat().st_size}:{weights.stat().st_mtime_ns}"
        self.fingerprint = hashlib.sha256(fingerprint.encode()).hexdigest()

    def synthesize(self, text, caption, voice, reference=None):
        seed = int.from_bytes(hashlib.sha256(voice.encode()).digest()[:4], "little")
        results = list(self.model.generate(text=text, caption=caption,
                       ref_audio=str(reference) if reference else None,
                       rng_seed=seed, max_seconds=30.0))
        if not results:
            raise RuntimeError("model returned no audio")
        sample_rates = {result.sample_rate for result in results}
        if len(sample_rates) != 1:
            raise RuntimeError("model changed sample rate")
        audio = self.np.concatenate([self.np.asarray(result.audio, dtype=self.np.float32).reshape(-1) for result in results])
        if not len(audio) or not self.np.isfinite(audio).all():
            raise RuntimeError("model returned empty or nonfinite audio")
        if float(self.np.max(self.np.abs(audio))) < 1e-5:
            raise RuntimeError("model returned silent audio")
        return audio, sample_rates.pop()

    def write_audio(self, path, audio, rate):
        # Keep the tiny atomic file-commit region noninterruptible: cancel may
        # discard the result, but must not leak temporary files or leave a partial
        # reference. Restoring the mask dispatches any pending cancel immediately.
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1})
        fd, tmp = None, None
        try:
            fd, tmp = tempfile.mkstemp(prefix=".irodori-", suffix=".wav", dir=path.parent)
            os.close(fd)
            fd = None
            self.sf.write(tmp, audio, rate, subtype="PCM_16")
            # Fail rather than overwrite an existing file, including a race/symlink.
            os.link(tmp, path)
        finally:
            try:
                if fd is not None:
                    os.close(fd)
                if tmp is not None:
                    os.unlink(tmp)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)

    def run(self, request):
        request_id, text, voice, instructions, output = request
        started = time.monotonic()
        key = hashlib.sha256((self.fingerprint + voice + PRESETS[voice] + REFERENCE_TEXT).encode()).hexdigest()
        reference = self.references / (key + ".wav")
        reference_created = False
        if reference.is_symlink():
            raise ValueError("reference audio must not be a symlink")
        if not reference.is_file():
            audio, rate = self.synthesize(REFERENCE_TEXT, PRESETS[voice], voice)
            self.write_audio(reference, audio, rate)
            reference_created = True
        generation_start = time.monotonic()
        caption = PRESETS[voice] + (" " + instructions if instructions else "")
        audio, rate = self.synthesize(text, caption, voice, reference)
        self.write_audio(output, audio, rate)
        return {"id": request_id, "ok": True, "output": str(output),
                "voice": voice, "duration_seconds": len(audio) / rate,
                "sample_rate": rate, "generation_seconds": time.monotonic() - generation_start,
                "total_seconds": time.monotonic() - started,
                "reference_created": reference_created, "reference": str(reference),
                "peak_memory_gb": self.mx.get_peak_memory() / 1e9,
                "duration_limited": len(audio) / rate >= 29.8}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    started = time.monotonic()
    try:
        with contextlib.redirect_stdout(sys.stderr):
            worker = Worker(args.model, args.output_dir)
        cancellation = Cancellation(worker.root)
        signal.signal(signal.SIGUSR1, cancellation.check)
        emit({"ready": True, "model": str(worker.model_path), "load_seconds": time.monotonic() - started})
    except Exception as error:
        emit({"ready": False, "error": str(error)})
        return 1
    while True:
        line = sys.stdin.readline(MAX_LINE + 1)
        if not line:
            return 0
        if len(line) > MAX_LINE:
            emit({"id": None, "ok": False, "error": "request line exceeds limit"})
            return 2
        request_id = None
        try:
            request = parse_request(line, worker.root)
            request_id = request[0]
            cancellation.begin(request_id)
            with contextlib.redirect_stdout(sys.stderr):
                result = worker.run(request)
            cancellation.check()
            cancellation.finish()
            emit(result)
        except Cancelled:
            cancellation.finish()
            emit({"id": request_id, "ok": False, "cancelled": True, "error": "cancelled"})
        except Exception as error:
            cancellation.finish()
            emit({"id": request_id, "ok": False, "error": str(error)})
        finally:
            cancellation.finish()


if __name__ == "__main__":
    raise SystemExit(main())
