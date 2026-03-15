# Ourin Extensions and Behavioral Notes

This document summarizes non-standard or platform-specific behavior in Ourin.

## Platform focus

Ourin is a macOS-native baseware. Several behaviors intentionally use AppKit/SwiftUI mechanics over strict SSP parity.

Examples:

- Window control and animation via `NSWindow` APIs
- Visual effects/state modeled through SwiftUI view models
- Native settings/open flows for browser, mail, dialogs

## SakuraScript execution model

Parser and executor are separated:

- `SakuraScriptEngine` tokenizes
- `GhostManager` interprets tokens and enqueues playback units

This supports typing effects, deferred commands, and command timing control.

## Extended move command handling

`move/moveasync` supports option-style forms:

- `--X`, `--Y`
- `--time`
- `--base`, `--base-offset`, `--move-offset`
- `--option=ignore-sticky-window`
- `moveasync,cancel` (with optional scope)

Positional legacy form is kept for compatibility.

## Window group control extensions

- `set,zorder` accepts broader scope-token parsing (`current`, `all`, delimited lists)
- `set,sticky-window` supports grouped forms (including `--group=...|...`)

These are practical extensions for multi-character window control on macOS desktops.

## Dressup/bind handling

`bind` supports:

- category form
- repeated tuple form
- disable/unbind semantic values (`0`, `false`, `off`, `none`, `default`)

Rendering is still partial; binding state is maintained for future full compositor behavior.

## SERIKO coexistence model

Ourin currently keeps:

- legacy `AnimationEngine` path
- new `SerikoParser` + `SerikoExecutor` path

Runtime uses executor first and can fall back to legacy engine when needed.

## SAORI host bridge

YAYA plugin operations are bridged to Swift host via JSON host operations:

- `saori_load`
- `saori_unload`
- `saori_request`

This is an Ourin architecture choice for stable Rust/C++/Swift boundary handling.

## Known compatibility notes

- Some SakuraScript subcommands are partially implemented (documented in `SUPPORTED_SAKURA_SCRIPT.md`)
- Full SSP-level behavior parity is still in progress for advanced animation/dressup combinations
- Existing test suite includes unrelated historical failures; feature validation is often done with focused test targets
