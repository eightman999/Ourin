# Corpus compatibility probes

Headless probes for extracted NAR roots (ghost / balloon / plugin). The parent harness supplies a disposable directory; these tools never modify the repository or user ghost stores.

## Parent runner

The sandbox parent is **`scripts/compatibility_corpus.py`** (maintained outside this package). It:

- Strips custom environment variables from the child process.
- Requires explicit CLI flags (`--cache-dir`, probe stdin JSON).
- Invokes `scripts/probe_corpus_content.py` under `sandbox-exec` with read-only cache and writable disposable item roots, plus the literal `/dev/null` needed for suppressed child stderr.

This directory intentionally does **not** ship a second runner.

## CLI contract

**Entry:** `scripts/probe_corpus_content.py`

| Flag | Required | Purpose |
|------|----------|---------|
| `--cache-dir ABS` | always | `/tmp/...` preflight artifacts (collector + balloon probe). Runtime is read-only. |
| `--preflight` | preflight only | Compile production YAYA collector + balloon probe into `--cache-dir`. |
| `--engine-dir ABS` | optional (repeat) | Trusted built SHIORI dylib directories for bundled/native resolution. |
| `--repo ABS` | optional | Repository root (default: parent of `scripts/`). |

**stdin (one JSON object, regular probe):**

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Opaque probe id (echoed in output). |
| `kind` | yes | `ghost`, `balloon`, or `plugin`. |
| `root` | yes | Absolute path to extracted corpus root (no symlinks on `root`). |
| `engine_hint` | no | Diagnostic hint only. |

**stdout:** exactly one JSON object (`pass` / `partial` / `unsupported` / `error`). No third-party dialogue text.

Runtime without required preflight artifacts reports `missing_preflight` (no cache writes); no runtime success is counted.

### Preflight

```bash
python3 scripts/probe_corpus_content.py --preflight \
  --cache-dir /tmp/ourin-corpus-probe-$UID
```

### Probe example

```bash
printf '%s' '{"id":"x","kind":"balloon","root":"/tmp/extract"}' | \
  python3 scripts/probe_corpus_content.py --cache-dir /tmp/ourin-corpus-probe-$UID
```

## Implementation references

| Area | Source of truth in Ourin |
|------|-------------------------|
| YAYA config / dictionaries | `Ourin/USL/ShioriLoader.swift` (`collectDicEntries`, `applyYayaBasePath`) via preflight collector |
| descript.txt parsing | `Ourin/Compat/LegacyDescriptor.swift` |
| SHIORI runtime / bundled engines | `ShioriRuntimeFactory.swift`, `BundledShioriEngine.swift` |
| Native ABI | `Ourin/USL/NativeShioriModule.swift`, `engines/additional/verify.py` (isolated worker) |
| Plugin metadata | `Ourin/PluginHost/PluginRegistry.swift` (`readMetaDictionary`, `nativePluginModules`) |
| Balloon static parse | `BalloonConfig.swift` + `balloon_probe_cli.swift` |

## Classification notes

- **Ghost:** Helper lifecycle (`load`, `OnBoot`, conversation with nonempty `Value`, `OnClose`, `unload`) is separate from tree-change observations. Second load is reported but not treated as proven persistence. Windows ghost DLLs are never executed.
- **Balloon:** Always at most `partial` (UI not verified).
- **Plugin:** Manifest / install layout only; `can_dispatch_requests` is always false without runtime load.

## Tests

```bash
python3 scripts/probe_corpus_content.py --preflight --cache-dir /tmp/ourin-corpus-probe-test
python3 -m unittest discover -s scripts/corpus_probe/tests -p 'test_*.py'
```

Fixtures under `scripts/corpus_probe/tests/temp/` are Ourin-authored only.

## Counting verification layers

`checks.runtime_executed` is true only after a SHIORI helper process is launched. A `pass` requires a complete successful load / OnBoot / nonempty conversation / OnClose / unload sequence and a successful second load / OnBoot / OnClose / unload cycle. A second-cycle failure is `partial` with `reopen_failed`. Missing external host capabilities prevent an unconditional pass. These are headless SHIORI checks, not GUI, full SAORI, or complete dictionary compatibility.

Balloon results set `checks.parser_executed: true` after running the production Swift parser and image decoder, and `checks.runtime_executed: false`. They remain `partial` because rendering is unverified. Plugin metadata inspection does not execute the plugin and sets runtime false. Do not combine balloon parsing counts with ghost runtime rates.

Changes in the disposable tree and second-session reopen results are observations. `save_file_observed: null` and `persistence_semantically_verified: false` avoid treating a new profile directory or arbitrary write as proof that state persisted correctly. Windows DLL files may remain in a known-engine ghost; the trusted macOS engine runs instead. Unknown DLLs and downloaded custom Mach-O modules are not loaded, even if the package declares a supported ABI in a plist. Native SHIORI resolution is restricted to recognized bundled names from trusted built-engine directories; this corpus restriction does not change Ourin application behavior.

## Reproducible trusted-engine invocation

Prepare once outside the corpus sandbox, then pass the same cache and trusted Frameworks folder to each probe. The runner supplies the disposable extraction root in stdin JSON and constrains its writes and network access.

```sh
python3 scripts/probe_corpus_content.py --preflight \
  --cache-dir /tmp/ourin-corpus-probe-final

# Use this argv with compatibility_corpus.py --probe-command-json:
python3 scripts/probe_corpus_content.py \
  --cache-dir /tmp/ourin-corpus-probe-final \
  --engine-dir /path/to/Ourin.app/Contents/Frameworks
```

The executable helper paths are the repository's existing `yaya_core/build/yaya_core` and `satori_core/build/satori_core`. `--engine-dir` is repeatable and is for trusted prebuilt macOS libraries, not downloaded Windows DLLs. Runtime does not compile Swift or install dependencies. If a helper, engine, or preflight artifact is absent, the report records that limitation instead of a success.

## Implementation and verification provenance (2026-10-25)

- The user-requested real Cursor CLI `/Users/eightman/.local/bin/agent` ran with `-p --model composer-2.5 --trust --auto-review --output-format text` in this checkout. Initial implementation completed with 6 tests passing. A corrective Cursor run encountered repeated API connection loss and was terminated; a single retry completed with 18 tests passing. No other model is counted as Cursor work.
- The coordinating Codex agent independently audited the result and corrected known-engine selection when a Windows DLL is present, complete lifecycle/conversation accounting, save-observation reporting, all-kind symlink checks, and runtime/parser measurement flags. Fifteen independent regression tests bring the suite to **33 tests**, including the outer timeout process-group boundary and an actual runner-sandbox YAYA lifecycle. The latter reproduced an engine-launch failure caused by denying `/dev/null` writes and passes with the runner's literal-path exception. The optional native-directory test requires `OURIN_CORPUS_ENGINE_DIR`; without it that test is explicitly skipped.
- The actual trusted libraries for **Akari, ese-shiori, Nise-shiori, Shino, Hisui, and Yuhna** passed load, OnBoot, nonempty conversation, OnClose, unload, and a second session using copies of Ourin-authored fixtures. Each copy also contained a harmless Windows DLL placeholder, verifying that its presence does not disable the corresponding macOS engine. These are fixture runtime checks, not distributed-ghost or screen checks.
- Real YAYA helper and production balloon parser/PNG decode were exercised by the suite. Separate self-authored samples passed the same lifecycle and reopen checks with the actual Satori helper and trusted KAGARI library (including c_long lengths, instance IDs, and unload success = 1). KAGARI/long/int32 ctypes bindings follow `NativeShioriModule.swift` and the existing engine verification scripts. Distributed-ghost outcomes belong to the corpus report, not these fixture results.
- Local delegation logs and metadata: `/tmp/ourin-corpus-cursor-20261025/` (`cursor.log`, `cursor-review.log`, `cursor-resume.log`, and result JSON files). These contain CLI provenance and are not downloaded ghost assets.

Native workers reserve a separate descriptor for JSON before loading a library; Lua/native stdout is routed to stderr and suppressed by the session. This prevents diagnostic output from becoming a false protocol failure, but an actual engine load failure remains a failure. An omitted `shiori` uses `shiori.dll`, matching Ourin and UKADOC, and is identified as YAYA only when its configuration supports that identification.

Probe tree inspection accepts at most 128 MiB across 5,000 files. Each file digest reads at most 8 MiB; larger files set `digest_complete: false`. The parent runner's archive expansion limit is separate and remains unchanged.

The permanent `tests/temp` files are minimal Ourin-authored fixtures. Test runs copy them to temporary directories; generated saves and Python bytecode are not committed. Third-party corpus assets are managed and removed by the parent runner, never vendored here.

## Process-group ownership and CI

The corpus runner sets `OURIN_CORPUS_PARENT_OWNS_GROUP=1`. SHIORI helpers then inherit the probe's process group, so the runner's timeout `killpg` reaches the probe and its helpers together. A session closes its direct child with terminate/kill in this mode; it never sends a signal to the runner-owned group itself. Standalone probing creates and manages a separate helper group as before. Regression tests check both modes and actual helper reaping after an outer group signal.

Tests assert the preflight JSON `status: ok` and `preflight.ok: true`, since the CLI's exit code alone does not establish successful compilation. Configure optional trusted-library inspection in CI with `OURIN_CORPUS_ENGINE_DIR=/path/to/Ourin.app/Contents/Frameworks`; no machine-specific engine directory is embedded in the tests.
