# Rishu/Proxy connection

[日本語](RISHU_ja-jp.md) · Updated: 2026-10-25

[User guide](https://furinlab.com/ourin/guide/) · [Published documentation](https://furinlab.com/ourin/docs/) · [Support and compatibility](https://furinlab.com/ourin/compatibility/)

As of 2026-10-25, this feature is implemented in development builds and is not included in the published release.

Development builds connect `shiori,rishu_proxy.dll` to the ghost's Perl `rishu_remote.pl`. This is experimental. The script and its Perl modules must be present beside the configured module path, preserving the distribution's layout (`lib/Rishu/Remote.pm` in the original sample). Direct Windows `rishu.dll` execution is unsupported.

## Runtime and transport

Perl must already exist; it is not bundled. The default is `/usr/bin/perl`. Set `OURIN_RISHU_PERL_EXECUTABLE` in Ourin's launch environment to an absolute executable path to use another installation. Compatibility with old Perl modules depends on that installation.

Ourin launches Perl with separate `rishu_remote.pl --port <ephemeral-port>` arguments. It does not execute shell commands from Windows `rishu_proxy.ini` or rewrite scripts/dictionaries.

Ourin binds a listener only to `127.0.0.1`. The upstream `--port` process is a client connecting to `INADDR_LOOPBACK`. The protocol uses `PROXY LOAD/REQUEST/UNLOAD/EXIT RISHU/1.1`, `Original-Response`, and `Content-Length`; it is distinct from SHIOLINK.

SHIORI defaults to Shift_JIS, with UTF-8 supported through the communication settings and `shiori.escape_unknown` honored. The LOAD directory must be representable in Shift_JIS. Startup and requests have deadlines, and frames are limited to 1 MiB. Failed startup, malformed output, or timeout invalidates the session and reaps the spawned process. Normal shutdown sends UNLOAD and EXIT. Further descendants and script-specific file writes remain the engine's responsibility.

## Verified scope

On 2026-10-25, the actual Swift adapter passed LOAD, Content-Length framing, GET/NOTIFY, Japanese Shift_JIS references, UNLOAD, EXIT, and PID reaping against the unmodified `rishu_remote.pl` in the [official 1.1.32 distribution](https://www.mikage.to/PerlShiori/snap/rishu-1.1.32.tar.gz). This sample echoes requests; it does not demonstrate a full personality ghost. Distributed ghosts such as Nayuki remain unverified.

Reproduce using a trusted extracted distribution. The script works on a temporary copy and does not download files or install Perl:

```sh
python3 scripts/verify_external_shiori.py rishu /path/to/rishu-1.1.32
```

`RishuProxyTests` exercises real Perl fixture processes for round trips, Unicode, failed startup, hangs, disconnects, malformed lengths, oversized frames, and process reaping.

Primary references: [author's page](https://www.mikage.to/PerlShiori/) and the distribution's `lib/Rishu/Remote.pm`, `rishu_remote.pl`, and `rishu_proxy.txt`. Upstream code and third-party ghosts are not redistributed in this repository.
