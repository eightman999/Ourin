# Known Issues and Verification Coverage

Updated: 2026-10-25. This document describes the development integration build, not a guarantee that changes are included in a published release. [日本語](KNOWN_ISSUES_ja-jp.md)

Use this document for defects and user-visible limitations, the [compatibility matrix](SHIORI_RUNTIME_COMPATIBILITY_MATRIX_ja-jp.md) for runtime implementation/test coverage, and the [TODO reconciliation](TODO_ISSUE_STATUS.md) for issue status. Distinguish implemented, locally integrated, verified with a real ghost, and fixed in a published release. Latest measurements are in the [real-ghost verification record](REAL_GHOST_VERIFICATION_2026-10-25.md) and [KAWARI/KAGARI guide](KAWARI_KAGARI_ENGINES_en-us.md); the detailed real-ghost measurement record is currently in Japanese.

## Limitations and unverified coverage

| Area | Current scope and impact | Tracking and action |
|---|---|---|
| Windows-only modules | Ourin does not directly execute Windows DLLs on macOS. SHIORI/SAORI support depends on macOS modules, built-in compatibility implementations, and each runtime's coverage. Renaming an extension does not make a module executable. | [#101](https://github.com/eightman999/Ourin/issues/101), [Native ABI](NATIVE_SHIORI_ABI_en-us.md). Report the public ghost name, version, and SHIORI type. |
| KAWARI/KAGARI coverage | Building an engine or passing a minimal dictionary test does not establish compatibility with every ghost, SAORI, or Lua extension. Real KAGARI ghosts also require validation of their native Lua dependencies. | [#101](https://github.com/eightman999/Ourin/issues/101). Check the engine guide and measurement records for the tested target and execution layer. |
| YAYA save formats and verification scope | The October 25 fixed build resolves Taromati2’s periodic-event hang. Emily4 and Taromati2 saved in Ourin’s format and reloaded in separate processes. Taromati2’s OnDestroy 400 is the dictionary’s expected response to an undefined event. Upstream text/encrypted save import/export remains unsupported; GUI and real SAORI integration remain unverified. | Related to [PR #191](https://github.com/eightman999/Ourin/pull/191). See the [real-ghost record](REAL_GHOST_VERIFICATION_2026-10-25.md). No identical-input comparison with an upstream binary was run. Existing saves in unknown formats are not overwritten. |
| Real-ghost coverage for SHIOLINK, SHIORI 2.x, and Native | Passing real fixtures or separate-process tests is distinct from checking every operation of distributed ghosts. Untested combinations of ghosts and external executables remain. | [#101](https://github.com/eightman999/Ourin/issues/101), [SHIOLINK](SHIOLINK_en-us.md). Unverified does not mean either unsupported or verified. |
| Saving after forced termination | Recovery from timeout/crash cannot restore unsaved VM state or SAORI side effects immediately before termination. | Reload starts from the last persisted state. Report save problems reproducible with normal shutdown using the [report guide](BUG_REPORT_GUIDE_en-us.md). |
| Diagnostic export coverage | Settings Export contains the last 24 hours of `jp.ourin.devtools` logs. It does not collect every SHIORI/helper log or OS/CPU/version field, and does not automatically anonymize data. The Debug menu's diagnostic export currently writes only a timestamp message. | [#104](https://github.com/eightman999/Ourin/issues/104). Use [log collection instructions](BUG_REPORT_GUIDE_en-us.md) for selected or file logs. Empty logs do not prove that no defect occurred. |
| Release-environment validation | Development targets now use macOS 13.0 or later, but minimum-OS, clean-Mac, and physical Intel release testing is not marked complete. This does not change the requirements of older distributed releases. | [#97](https://github.com/eightman999/Ourin/issues/97), [#102](https://github.com/eightman999/Ourin/issues/102), [release gates](RELEASE_GATES_2026-10-25.md). |
| Deferred/out-of-scope integrations | The Windows FineFMO shared-memory contract and IP Messenger/MsgSender integration are deferred. They are distinct from ordinary POSIX FMO. `mcp.exe` is recorded as outside Ukagaka compatibility scope. | [#124](https://github.com/eightman999/Ourin/issues/124), [#122](https://github.com/eightman999/Ourin/issues/122), [#114](https://github.com/eightman999/Ourin/issues/114). |

## Recording resolved issues

An old issue title saying “not implemented” may no longer describe the implementation. See the [PR takeover record](PR_TAKEOVER_2026-10-25.md) for integrated changes and validation. Local integration alone does not close a GitHub issue or establish inclusion in a distributed release.

When fixing an item, record the issue/PR, verification date, tested commit/version, and reproduction result in its row. After publication, add the released version and move the entry to resolved status, preserving information relevant to users of older builds. Release notes should link this document and describe release-specific limitations.

## Reporting

Use the [Bug Report Guide](BUG_REPORT_GUIDE_en-us.md) for symptoms not listed here or still reproducible in a fixed build. Environment, reproduction steps, expected behavior, and actual results are enough to begin a report; logs and ghost data are not required.

Translation: body, tables, and link targets checked against the [Japanese version](KNOWN_ISSUES_ja-jp.md) on 2026-10-25. Keep both languages synchronized when updating.
