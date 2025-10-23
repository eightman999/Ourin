# Translation Workflow for Ourin Documentation

This document describes the workflow for translating documentation between English and Japanese using gemini-cli.

## Current Status

✅ **All 36 documents now have both EN and JA files**

- 5 documents have actual translations
- 31 documents have placeholder files marked "Translation Pending"

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

### Priority 1: Core Specifications (22 files)
Essential technical specifications that developers need:
- SHIORI_3.0M_SPEC
- SSTP_1.xM_SPEC
- SPEC_PLUGIN_2.0M
- OURIN_YAYA_ADAPTER_SPEC_1.0M
- And others (see manifest)

### Priority 2-6: Supporting Documentation
UI mockups, implementation reports, and supporting materials.

## Using gemini-cli for Translation

### Batch Translation Commands

For translating JA → EN (most files):

```bash
# Example for a single file
gemini-cli translate \
  --source docs/SHIORI_3.0M_SPEC_ja-jp.md \
  --target docs/SHIORI_3.0M_SPEC_en-us.md \
  --source-lang ja \
  --target-lang en \
  --preserve-code \
  --preserve-structure
```

For translating EN → JA (fewer files):

```bash
gemini-cli translate \
  --source docs/PropertySystem_en-us.md \
  --target docs/PropertySystem_ja-jp.md \
  --source-lang en \
  --target-lang ja \
  --preserve-code \
  --preserve-structure
```

### Batch Processing Script

```bash
#!/bin/bash
# translate_batch.sh - Example batch translation script

# Files needing JA → EN translation
JA_TO_EN=(
  "SHIORI_3.0M_SPEC"
  "SSTP_1.xM_SPEC"
  "SPEC_PLUGIN_2.0M"
  # ... add more from TRANSLATION_MANIFEST.md
)

for base in "${JA_TO_EN[@]}"; do
  echo "Translating ${base} (JA → EN)..."
  gemini-cli translate \
    --source "docs/${base}_ja-jp.md" \
    --target "docs/${base}_en-us.md" \
    --source-lang ja \
    --target-lang en \
    --preserve-code \
    --preserve-structure \
    --overwrite
done
```

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

1. Remove "Translation Pending" status from translated file
2. Add translation metadata (translator, date, review status)
3. Update TRANSLATION_MANIFEST.md to mark file as complete
4. Regenerate HTML documentation

## Notes

- Placeholders should be completely replaced, not edited
- Preserve the original file's structure exactly
- Technical specifications require careful review
- Consider splitting large files into sections for easier translation
- Keep translation memory/glossary for consistency
