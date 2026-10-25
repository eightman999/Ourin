# Optional local Irodori runtime

This is a separately installed Apple Silicon runtime, not a bundled CeVIO or
A.I.VOICE engine. The presets are original synthetic voices, not the products'
voice identities. Their fixed reference utterances stabilize the selected voice
across requests and restarts; exact voice identity/expressiveness is still a
perceptual validation item.

## Reproduce the tested environment

The tested runtime is Python 3.13.11, mlx-audio 0.6.1, MLX 0.32.4 on macOS arm64.
Use a dedicated environment; do not install into the system Python:

```sh
python3.13 -m venv build/tts-runtime
build/tts-runtime/bin/python -m pip install -r engines/tts/requirements-lock.txt
build/tts-runtime/bin/python engines/tts/download_model.py \
  --destination "$HOME/dev/data/models/irodori-tts-v4.1-small-mf-fp16"
```

`download_model.py` downloads only when the destination is absent. If it already
exists, it verifies the pinned files and refuses mismatches without overwriting
or deleting data. `DEPENDENCIES.json` records the model revision and SHA-256
checksums. The snapshot is about 1.98 GB (decimal); the tested virtual environment
uses about 461 MiB. Reuse the shared model directory instead of copying it into
plugins or the app.

The model is
[mlx-community/Irodori-TTS-v4.1-Small-MF-fp16](https://huggingface.co/mlx-community/Irodori-TTS-v4.1-Small-MF-fp16),
revision `db0263236d010d4beb6ca67c529f410a6f71d755`. Its
[upstream model card](https://huggingface.co/Aratako/Irodori-TTS-v4.1-Small-MF#-license--ethical-restrictions)
provides the MIT license and additional ethical restrictions. Model weights are
not stored in this repository or the `.plugin` packages.

## Worker protocol

```sh
mkdir -p build/tts-audio
build/tts-runtime/bin/python engines/tts/irodori_worker.py \
  --model "$HOME/dev/data/models/irodori-tts-v4.1-small-mf-fp16" \
  --output-dir build/tts-audio
```

The first stdout line is `{"ready":true,...}` after loading. Write one request per
line to stdin, for example:

```json
{"id":"demo","text":"こんにちは。今日はいい天気ですね。","voice":"IrodoriAkari","instructions":"穏やかに話す。","speed":1.0,"output":"demo.wav"}
```

Voice IDs are `IrodoriAkari`, `IrodoriAoi`, and `IrodoriNagi`. An explicit output
must be a new `.wav` inside the configured output directory. The worker returns
`id`, `ok`, `output`, `duration_seconds`, `generation_seconds`, `total_seconds`,
`reference_created`, `peak_memory_gb`, and `duration_limited`. Errors return
`ok:false`. All third-party diagnostic output is redirected to stderr. The
worker sets Hugging Face and Transformers offline modes and requires the local
codec/tokenizer files, so synthesis does not fetch data over the network.

Each voice's first request generates a fixed reference sentence in
`output-dir/references/`. Later requests use that reference with the selected
style caption. The cache key includes the model path/config/weight metadata and
preset definition. Changing the model creates a new reference rather than using
an incompatible one. Preserve the directory for cross-restart voice continuity.

Output is mono 48 kHz PCM16. The host owns playback, queuing, cancellation,
pitch/rate/gain processing and punctuation pauses. The worker accepts only
`speed:1.0` so unsupported speed changes cannot silently succeed. Each request is
limited to 240 characters and generation to 30 seconds; the host should split
long text. A result near the duration cap is flagged `duration_limited` and must
not be treated as proof of complete reading.


## In-flight cancellation

The host creates an empty marker atomically at
`output-dir/.cancel-<sha256(str(request_id).encode()).hexdigest()>`, then sends
`SIGUSR1` to the worker PID. Only the currently active matching request is
cancelled. An idle signal is ignored; a marker created before stdin dispatch is
checked when that request starts, so the signal-before-request race is covered.
The reply is `{"id":"...","ok":false,"cancelled":true,"error":"cancelled"}`.
The worker removes the marker and keeps the loaded model for the next request.
Repeated signals cannot interrupt exception cleanup.

This is cooperative cancellation at Python execution boundaries. A running MLX
GPU/C++ operation must return before Python can process the signal; it is not a
hard real-time GPU abort. The brief atomic WAV commit region masks SIGUSR1 so a
cancel cannot leave a partial reference or temporary WAV. A completed output
may therefore exist if cancellation arrives at the commit boundary; the host
must discard cancelled results and stop active playback independently.

## Validation

```sh
python3 engines/tts/test_irodori_worker.py
```

These thirteen tests cover input bounds, explicit voices/rate handling, path
containment, symlink escape, reference-directory reservation, and non-overwriting
atomic output, and cancellation before/during dispatch. They do not load a model. Real synthesis must additionally check
output WAVs and timing with the installed model; passing protocol tests alone is
not proof of voice quality or commercial-product equivalence.
