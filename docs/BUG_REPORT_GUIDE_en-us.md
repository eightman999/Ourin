# Bug Report Guide

Updated: 2026-10-25. [日本語](BUG_REPORT_GUIDE_ja-jp.md) / [Known Issues](KNOWN_ISSUES_en-us.md)

Check [existing issues](https://github.com/eightman999/Ourin/issues) and Known Issues first. If no matching report exists, use the [Bug report template](https://github.com/eightman999/Ourin/issues/new?template=bug_report.md). “Unknown” or “not performed” is acceptable for information or checks you cannot provide.

## Minimum useful information

- Ourin version/build (from About Ourin), download source or development commit.
- macOS version, Intel/Apple Silicon, and whether Rosetta was used if known.
- Public ghost name/version/download URL and SHIORI type/version if known. Relevant shell, balloon, SAORI, or plugin.
- Reproduction steps, expected and actual behavior, frequency, and occurrence time/timezone.
- Whether the problem occurs during startup, conversation, saving, or after restarting. You do not need to delete real save data to investigate.

If the ghost name or download URL cannot be shared publicly, say so and discuss a redistributable minimal fixture. Private dictionaries, conversations, NARs, and save files are not required report materials.

## Collecting logs

The following controls were verified in the current source. If your release or language setting shows different labels, report the version and visible labels.

### Copy only relevant entries

1. Open Ourin's `Settings...` (⌘,) and select `Logging & Diagnostics`.
2. Set `Since` to cover the occurrence and choose the relevant `Subsystem`, then click “更新” (Refresh).
3. Select related entries around the failure and click “コピー” (Copy). Paste them into a separate text file for sharing, then apply the redactions below.

### Export from Settings

Use the share icon (upward arrow, tooltip `Export`) at the top of Settings to create `OurinDiagnostics.txt` and reveal it in Finder. The file is in a temporary directory; save relevant excerpts in a separate sharing copy.

**This export covers only the last 24 hours of `jp.ourin.devtools`.** It does not follow the visible log filters, collect all SHIORI/helper logs, or bundle environment information. **The Debug menu's diagnostic export currently writes only a timestamp message**; do not treat that output as a complete diagnostic report. If zero entries are found, report that fact and the reproduction time.

### When a file log is needed

1. In Settings → `General` → “ログ設定” (Log settings), enable “ファイルへのログ出力を有効化” (Enable file logging).
2. Check the displayed log output path and click “設定を保存” (Save settings). The default is `Library/Logs/Ourin/ourin.log` under the app's home directory; use the actual path shown in Settings.
3. Note the time, reproduce once, and copy only the relevant surrounding lines into a sharing copy.
4. After investigation, turn the toggle off and save settings. You do not need to delete existing logs or real ghost data.

File logging captures entries sent through `Log`; it does not cover every OSLog entry, helper stderr, or third-party output. If no file is produced, you may report that logs could not be obtained.

## Before sharing

GitHub issues are public. Automatic anonymization is not guaranteed. **Leave original data unchanged and inspect a sharing copy**, removing:

- API keys, tokens, passwords, cookies, Authorization headers, private keys, and `.env` contents.
- Personal paths such as `/Users/real-name/...`, usernames, email addresses, and device identifiers. For example, replace a path with `/Users/<user>/...`.
- Private conversations, dictionaries, saved content, clipboard contents, external request/response bodies, private URLs, and hostnames.
- Other apps, notifications, and account names in screenshots. Crop to the relevant area.

Preserve error codes, event names, relative timing, and extensions where possible. If safe redaction is difficult, report the symptom without attachments. Publishing a full `sysdiagnose`, home folder, or ghost directory is unnecessary.

## Crashes and hangs

Report which process exited (for example, Ourin / yaya_core / satori_core / OurinShioriXPCService), the time, the preceding operation, and whether the main app also exited. If macOS Console contains a matching crash report, attach redacted excerpts covering version/OS/architecture, Exception/Termination Reason, and the relevant thread. Remove personal paths and identifiers; “unavailable” is acceptable if no report exists.

For a hang, report how long you waited and whether only the display or also conversation/quit operations stopped responding. You do not need to repeatedly reproduce long hangs or delete unsaved data for diagnosis.

## Implementation evidence and remaining work

Control labels and collection scope were checked in [ContentView.swift](../Ourin/ContentView.swift), [DevToolsCommands.swift](../Ourin/DevTools/DevToolsCommands.swift), and [Log.swift](../Ourin/Utils/Log.swift) as of 2026-10-25. This is source verification, not a new GUI execution test. Environment export, unified export entry points, and anonymization remain candidates for further implementation/validation under [#104](https://github.com/eightman999/Ourin/issues/104).

Translation: procedures, limitations, and privacy guidance checked against the [Japanese version](BUG_REPORT_GUIDE_ja-jp.md) on 2026-10-25.
