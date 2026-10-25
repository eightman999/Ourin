# SHIOLINK external process transport

[日本語](SHIOLINK_ja-jp.md) · Updated: 2026-10-25

[User guide](https://furinlab.com/ourin/guide/) · [Published documentation](https://furinlab.com/ourin/docs/) · [Support and compatibility](https://furinlab.com/ourin/compatibility/)

The Ourin development build routes `shiori,SHIOLINK.dll` to an external SHIOLINK process. It does not load a Windows DLL. Supply a macOS runtime such as Node.js or Ruby and a SHIOLINK-speaking engine separately. This does not guarantee compatibility with every MiyoJS dictionary.

## Configuration

Ourin first reads `SHIOLINK.ourin.ini` beside the declared DLL (normally `ghost/master`), then `SHIOLINK.INI` only if the first file is absent. Filenames and keys are case-insensitive. Configuration is limited to 64 KiB, encoded as UTF-8 or Shift_JIS. An invalid preferred file does not trigger fallback.

The Ourin format separates the executable from its arguments:

```ini
[SHIOLINK]
executable=/opt/homebrew/bin/node
arguments=["./node_modules/miyojs/bin/miyo-shiolink.js", "./dic"]
charmode=UTF-8
```

This configuration was verified against the actual npm `miyojs@2.0.3` package. `bin/miyo-shiolink.js` is its shipped entry point; the next argument, `./dic`, selects the dictionary directory.

`arguments` is a JSON string array. Adjust the Node path, script and dictionary directory to your installation. Ourin does not install runtimes or npm packages automatically.

The shared `commandline` format also accepts quoted arguments:

```ini
[SHIOLINK]
commandline=/opt/homebrew/bin/node "./node_modules/miyojs/bin/miyo-shiolink.js" "./dic"
charmode=UTF-8
```

Execution uses `Process.executableURL` and `arguments`, without an implicit shell. Nested/escaped quotes, variable expansion, pipes and redirection are unsupported. Use the JSON format for complex arguments. Windows executable names (`.exe`, `.cmd`, etc.) are rejected. Relative paths and the working directory are based on the DLL directory. Bare executable names are searched there, then in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` and `/bin`.

The child inherits Ourin's execution privileges. This transport adds no separate sandbox or automatic SAORI forwarding.

## Communication and failure handling

- Ourin sends `*L:directory`, followed by a `version` request and waits for its response. SHIOLINK has no dedicated load acknowledgment; this verifies communication, not the validity of every dictionary.
- Each request checks a unique `*S:identifier` echo before sending the SHIORI message. GET and NOTIFY use the same transport.
- After `*U:`, Ourin waits briefly for clean exit, then sends TERM and KILL if necessary and reaps its direct child.
- Initialization defaults to five seconds. Requests use the caller's timeout, capped at 60 seconds. A single deadline covers writes, synchronization and reads. Invalid echo, EOF, malformed response, timeout, or a request/response over 1 MiB closes the session. There is no automatic restart; reloading the ghost reconnects.
- `charmode` supports UTF-8 (default) and Shift_JIS. UTF-16/32 cannot use the byte-oriented line framing and are rejected. Unencodable outgoing characters fail the operation. stderr is discarded rather than accumulated.

SHIORIPROXY, Rishu's dedicated proxy protocol and Windows DLL execution are outside this feature. Engines remain responsible for descendant processes they launch.

## Validation

`ShiolinkTests` launches a real C fixture to check Unicode round trips, GET/NOTIFY, the load directory, unload, synchronization errors, hangs, excessive output, EOF, child cleanup and configuration precedence. Compatibility testing with real MiyoJS ghosts remains separate.

## Primary references

- [ShiolinkJS transport](https://github.com/Narazaka/shiolinkjs/blob/master/lib/shiolink.ts)
- [ShiolinkJS usage](https://github.com/Narazaka/shiolinkjs/blob/master/Readme.md)
- [Sana SHIOLINK.INI example](https://github.com/Narazaka/sana/blob/master/README.md)

## Actual MiyoJS engine verification

On 2026-10-25, the actual adapter passed LOAD, OnBoot, Japanese/emoji output, OnClose, UNLOAD, and PID reaping using official npm MiyoJS 2.0.3, shiolinkjs 1.x, js-yaml 3.14.1, and an existing macOS Node.js installation. The dictionary was a minimal validation YAML file. MiyoJS 2.0.3 calls `safeLoad` and needs js-yaml 3.x; upgrading to 4.x is incompatible.

The author's MiyoPreview NAR download timed out and could not be obtained, so distributed-ghost verification remains outstanding. Additional filters and full dictionary compatibility are not verified. For a prepared master directory containing its Node configuration and node_modules, run the following; it uses a temporary copy and preserves the original:

### Preparing a validation master directory

Run this from the Ourin repository root with Node.js, npm, Python 3, and Xcode Command Line Tools already installed. It creates a new `/tmp` directory containing pinned dependencies, a minimal dictionary, and configuration using the current Node.js executable's absolute path. It does not write to existing ghosts. This is a minimal engine sample, not a complete distributed ghost with a shell.

```sh
# Run from the Ourin repository root; Node.js, npm and Python 3 must be installed.
miyo_master="$(mktemp -d -t ourin-miyo-master)"
npm install --prefix "$miyo_master" --ignore-scripts --no-audit --no-fund --save-exact \
  miyojs@2.0.3 js-yaml@3.14.1 shiolinkjs@1.0.1 shiorijk@0.0.1 es6-promise@2.3.0
mkdir "$miyo_master/dic"
cat > "$miyo_master/dic/main.yaml" <<'YAML'
version: "2.0.3"
OnBoot: \h\s[0]起動。\e
OnClose: \h\s[0]終了。\e
OnUnicode: 桜鈴 🌸
YAML
node - "$miyo_master" <<'JS'
const fs = require('fs');
const path = require('path');
const args = ['./node_modules/miyojs/bin/miyo-shiolink.js', './dic'];
fs.writeFileSync(path.join(process.argv[2], 'SHIOLINK.ourin.ini'),
  `[SHIOLINK]\nexecutable=${process.execPath}\narguments=${JSON.stringify(args)}\ncharmode=UTF-8\n`);
JS
python3 scripts/verify_external_shiori.py miyo "$miyo_master"
```

The final command checks actual-adapter LOAD, OnBoot, OnClose, UNLOAD, and child reaping. Keep the generated `package-lock.json`; running `npm ci --ignore-scripts --no-audit --no-fund` inside that master directory reproduces its resolved dependencies.

See the [Rishu guide](RISHU_en-us.md) for its separate TCP transport.
