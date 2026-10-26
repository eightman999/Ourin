# TMIDI Messages — Ourin native bridge

This is an independent Apache-2.0 implementation of the TMIDI plugin's event and
template behavior. It is not a macOS build of TMIDI Player. A Windows machine
running TMIDI Player is still required to obtain actual DDE playback information.
The Windows producer is implemented but **has not been tested on Windows**.

## Setup

1. On Windows, start TMIDI Player, then run Python 3:

   ```powershell
   py tmidi_windows_bridge.py --port 50002
   ```

   The producer binds only `127.0.0.1`. It queries the DDE service/topic `TMIDI`
   using `getstatus`, `getplayfile`, `getfilename N`, and `gettitle N`. It does not
   issue DDE execute or poke commands, modify player settings or start playback.

2. Explicitly forward that loopback port to your Mac using an existing, authorized
   SSH connection to the Windows machine, for example:

   ```sh
   ssh -N -L 127.0.0.1:50002:127.0.0.1:50002 YOUR_WINDOWS_SSH_HOST
   ```

   This project does not install an SSH server, open a firewall or expose a public
   listener. Configure that connection separately. Do not forward the bridge to
   a public interface: it returns local playback names without authentication.

3. Create `Contents/Resources/tmidi-bridge.json` inside the generated `.plugin`:

   ```json
   {"port":50002}
   ```

   Alternatively set `OURIN_TMIDI_BRIDGE_PORT` in the actual Ourin process
   environment. A GUI launched from Finder does not inherit a shell's variables.
   The plugin itself always connects to `127.0.0.1`; a hostname cannot be supplied.
   Without configuration it reports `503 tmidi_bridge_not_configured`.

The original `sstp_sample.txt` can be retained unchanged at
`Contents/Resources/payload/sstp_sample.txt` (or `Resources/sstp_sample.txt`). UTF-8
and Windows Japanese code-page templates are accepted. `#NoWRD`, `#MIMPIWRD`,
`#SherryWRD`, `#NeoWRD`, `$title`, `$format` follow the original interface. The
Windows producer determines companion WRD files on the Windows filesystem.

## Local transport

Each `OnSecondChange` makes one TCP connection with a two-second overall deadline.
The request and response are one UTF-8 JSON line each. A response is limited to
1 MiB and 32 instances. No configured bridge, connection failure, DDE failure,
invalid response or oversize response is treated as successful playback.

Request:

```json
{"protocol":"ourin-tmidi-dde/1","service":"TMIDI","topic":"TMIDI","query":"snapshot"}
```

Example **fixture** response (not evidence of actual player execution):

```json
{"protocol":"ourin-tmidi-dde/1","session":"producer-process-id","instances":[{"id":"conversation-id","getstatus":"play","getplayfile":"0","getfilename":"C:\\Music\\example.mid","gettitle":"Example","wrd":"NoWRD"}]}
```

The producer session changes on restart. Initial already-playing songs are
suppressed; stop followed by play and track changes emit a `Script`. Pause/resume
does not reannounce the same track. Changes from multiple instances are delivered
on successive polls. Titles have backslashes escaped and CR/LF flattened.
`OnMenuExec` and unrelated events have no payload, as in the original plugin.

The producer's error response has an `error` field, and no successful `instances`
snapshot. A bridge cannot synthesize a successful empty list after DDE failure.

## Validation boundary

`test_tmidi.py` builds and loads the real macOS dylib, communicates with a synthetic
loopback producer, and verifies event transitions, templates, Japanese text,
duplicate instances, bridge failures, and producer query validation. This proves
the macOS adapter and transport, not Windows DDE/actual TMIDI integration.

Sources consulted: [original plugin](https://github.com/JiayuYangX/tmidi_msg/blob/main/tmidi_msg.cpp),
[DdeConnectList](https://learn.microsoft.com/en-us/windows/win32/api/ddeml/nf-ddeml-ddeconnectlist),
[DdeClientTransaction](https://learn.microsoft.com/en-us/windows/win32/api/ddeml/nf-ddeml-ddeclienttransaction),
[DdeInitializeW](https://learn.microsoft.com/en-us/windows/win32/api/ddeml/nf-ddeml-ddeinitializew).
No original C++ implementation or player binary is included.
