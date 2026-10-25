# SHIOLINK external process transport

[日本語](SHIOLINK_ja-jp.md) · Updated: 2026-10-25

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

`arguments` is a JSON string array. Adjust the Node path, script and dictionary directory to your installation. Ourin does not install runtimes or npm packages automatically.

The shared `commandline` format also accepts quoted arguments:

```ini
[SHIOLINK]
commandline=/opt/homebrew/bin/node "./engine/main.js"
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
