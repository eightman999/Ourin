# BALLOON/1.0M — Ourin (macOS) Balloon Specification (Draft)
**Status:** Draft / macOS 10.15+ / Universal 2 (arm64, x86_64)
**Updated:** 2025-07-27 (JST)
**Compatibility Policy:** Maintain **vocabulary and behavioral compatibility** with UKADOC "Balloon Settings" and related specifications (descript.txt / balloons*s.txt, etc.), while replacing windowing, rendering, and input with **native macOS APIs**.
**Non-Goals:** Replicating Windows-specific UI, registry, or GDI-compliant behavior (limited to vocabulary and behavioral compatibility).

---

## Table of Contents
- [1. Scope and Coverage](#1-scope-and-coverage)
- [2. File Structure and Character Encoding](#2-file-structure-and-character-encoding)
- [3. Image Formats and Transparency (SSP Compatible)](#3-image-formats-and-transparency-ssp-compatible)
- [4. Rendering (Retina/Multi-display)](#4-rendering-retinamulti-display)
- [5. Window Characteristics (Foreground/Non-activating/Hit-testing)](#5-window-characteristics-foregroundnon-activatinghit-testing)
- [6. Text Rendering and Decoration](#6-text-rendering-and-decoration)
- [7. Input Box and Associated Assets](#7-input-box-and-associated-assets)
- [8. Compatibility Options (Windows→macOS Replacements)](#8-compatibility-options-windowsmacos-replacements)
- [9. Error Handling](#9-error-handling)
- [10. Conformance Checklist](#10-conformance-checklist)
- [Appendix A. Key Correspondence (Difference Memo)](#appendix-a-key-correspondence-difference-memo)
- [Appendix B. Image Loading Pipeline](#appendix-b-image-loading-pipeline)

---

## 1. Scope and Coverage
- Settings from `descript.txt` and overrides from `balloons*s.txt/balloonk*s.txt/balloonc*s.txt` will be **interpreted equally**.
- Inherit the **meaning of asset names** such as `arrow*.png`, `online*.png`, and `sstp.png`.

## 2. File Structure and Character Encoding
- **UTF-8 is standard**. If `charset,Shift_JIS` is specified in `descript.txt` or similar files, it will be **accepted as CP932**.
- Files are located under the baseware's balloon storage folder (same as UKADOC).

## 3. Image Formats and Transparency (SSP Compatible)
- **Supported Read Formats (Compatible)**: **BMP / PNG / JPEG / GIF / MAG / XBM / PI / ICO / CUR**.
  - Default is **Image I/O** (for common formats like PNG/JPEG/GIF/BMP).
  - **ICO/CUR** use a built-in parser (see the minimal implementation in this distribution).
  - **MAG / PI / XBM** will be provided incrementally through an **extended decoder SPI**.
- Supports **transparent display with 32-bit PNG (RGBA)** (alpha blending).
- Also compatible with **PNA** (separate alpha file).

## 4. Rendering (Retina/Multi-display)
- Coordinates are described in **logical pixels**. During rendering, the resolution is selected according to the **backingScaleFactor** to **ensure a consistent appearance even at high DPI**.
- When the screen moves or the scale changes, hook `viewDidChangeBackingProperties` to recalculate image/font scales.

## 5. Window Characteristics (Foreground/Non-activating/Hit-testing)
- Based on **NSPanel (nonactivating)**, display in the foreground **without stealing focus** (using an appropriate level like `.floating`).
- For click-through, override `NSView.hitTest(_:)` to **pass only transparent pixels to the background** (for full transparency, `ignoresMouseEvents=true` is also an option).

## 6. Text Rendering and Decoration
- Font resolution is handled by **NSFont/CTFont**. A fallback font is used if not installed.
- Bold/italic/underline/strikethrough/shadow/outline are represented by **NSAttributedString** attributes.
- The default wrapping is **byCharWrapping**. If necessary, extend with Core Text for line-breaking rules (kinsoku), ruby text, etc.

## 7. Input Box and Associated Assets
- `communicatebox.*` is reproduced with an **NSTextView equivalent** (translucency with `use_input_alpha`).
- Inherit the meaning and priority of `arrow*.png`, `online*.png`, `sstp.png`, `marker.png`, etc.

## 8. Compatibility Options (Windows→macOS Replacements)
- `cursor.style` is reproduced by drawing a rectangle/underline.
- `wordwrappoint.x` is reflected in the Core Text layout width.
- Recommended ghosts (`recommended.*`) display a warning in the UI.

## 9. Error Handling
- For unknown keys, log a warning and **continue with the default value**.
- For missing fonts or image loading failures, notify the UI and apply a fallback.
- On scale changes, perform an **immediate relayout** to suppress fringing.

## 10. Conformance Checklist
- [ ] Implement the **override rules** for `descript.txt` and `balloons*s.txt`.
- [ ] **Standard UTF-8 / Accept CP932**.
- [ ] Read **PNG/JPEG/GIF/BMP** (Image I/O).
- [ ] Read **ICO/CUR** (built-in parser).
- [ ] **MAG/XBM/PI** are extensible via SPI.
- [ ] Correctly handle transparency with **32-bit PNG alpha**.
- [ ] Equivalent display on **Retina/multi-display** setups.
- [ ] **Non-activating foreground** + **transparent hit-testing**.

---

## Appendix A. Key Correspondence (Difference Memo)
- `font.*`, `validrect.*`, `origin.*`, `windowposition.*`, `use_self_alpha`, `use_input_alpha`, `paint_transparent_region_black`, `overlay_outside_balloon`, `communicatebox.*`, `arrow/online/sstp/marker` … **Support UKADOC vocabulary as is**.

## Appendix B. Image Loading Pipeline
```
Data -> (UTI estimation) -> Image I/O (PNG/JPEG/GIF/BMP)
                         -> ICO/CUR built-in parser (PNG payload or 32bpp BMP→RGBA)
                         -> MAG/PI/XBM: Ourin Decoder SPI (extension)
```

---

### Reference (Implementation Notes)
- ICO/CUR files have an **ICONDIR + ICONDIRENTRY** header. Each entry contains either **PNG or DIB (BMP)** data. CUR has a **hotspot(x,y)** in the position of the planes/bitcount fields of the ICONDIRENTRY. A 32bpp BMP is treated as BGRA with alpha; if the alpha is all zeros, it is supplemented with an AND mask.
- Retina support utilizes `backingScaleFactor` and `viewDidChangeBackingProperties()`.
- Non-activating foreground uses a **nonactivatingPanel**, and click-through is controlled by **hitTest**.
