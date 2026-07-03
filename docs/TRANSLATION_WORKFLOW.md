# Translation Workflow for Ourin Documentation

This document describes the workflow and guidelines for translating documentation between English and Japanese.

## Current Status

⚠️ **Re-audited 2026-07-02: 37 of 57 documentation pairs are complete (65%); 20 pairs still
have a "Translation Pending" placeholder stub on one side.** The previous "100% coverage /
61 pairs" claim was stale — it counted a file existing on both sides as "done" without
checking whether the content was a real translation or a placeholder. See
[TRANSLATION_MANIFEST.md](./TRANSLATION_MANIFEST.md) for the verified per-file breakdown.

- Every spec, guide, plan, summary, and audit report under `docs/` exists in both
  `*_ja-jp.md` and `*_en-us.md` (56 pairs), plus `DEPENDENCIES_ja-jp.md` / `DEPENDENCIES_en-us.md`
  (1 pair) — 57 pairs total, all using the same naming scheme as of 2026-07-02 (the former
  `DEPENDENCIES.ja.md` / `DEPENDENCIES.en.md` legacy pair was renamed to match).
- Original unsuffixed working docs are left in place; translated counterparts were added beside them.
- Translations follow consistent terminology and formatting (see guidelines below).

## File Naming Convention

All documentation files follow this naming pattern:

- Japanese: `{DocumentName}_ja-jp.md`
- English: `{DocumentName}_en-us.md`

## Placeholder Format

Placeholder files contain:
- Status header indicating "Translation Pending"
- Link to the source document
- Translation guidelines
- Metadata (translator, review status, dates)

## Translation Priority

See [TRANSLATION_MANIFEST.md](./TRANSLATION_MANIFEST.md) for the complete prioritized list.

### Priority 1: Core Specifications
Essential technical specifications that developers need:
- SHIORI_3.0M_SPEC
- SSTP_1.xM_SPEC
- SPEC_PLUGIN_2.0M
- OURIN_YAYA_ADAPTER_SPEC_1.0M
- And others (see manifest)

### Priority 2-6: Supporting Documentation
UI mockups, implementation reports, and supporting materials.

## Translation Guidelines

### Technical Terminology

Keep these terms in English in both versions:
- API names: `shiori_load()`, `shiori_request()`
- Technical terms: Bundle, Plugin, XPC, FMO
- Protocol names: SHIORI, SSTP, SAORI
- Data types: `UTF-8`, `CRLF`, `unsigned char*`

### What to Translate

DO translate:
- Section headings and titles
- Narrative descriptions and explanations
- Comments in code examples
- Status messages and notes
- Implementation guidelines

DO NOT translate:
- Code examples (except comments)
- File paths and filenames
- Environment variable names
- Configuration keys
- Error codes and constants

### Format Preservation

Maintain:
- Markdown structure (headings, lists, tables)
- Code block formatting and language tags
- Link references and anchors
- Table of contents structure
- Metadata headers

## Quality Assurance

After translation:

1. **Technical Review**: Verify technical accuracy
2. **Consistency Check**: Ensure terminology matches other docs
3. **Format Check**: Verify markdown structure is intact
4. **Link Check**: Ensure all links still work
5. **Code Check**: Verify code examples are unchanged

## Post-Translation Steps

1. Add translation metadata (translator, date, review status)
2. Update TRANSLATION_MANIFEST.md to mark file as complete
3. Regenerate HTML documentation

## Notes

- Preserve the original file's structure exactly
- Technical specifications require careful review
- Keep translation memory/glossary for consistency
