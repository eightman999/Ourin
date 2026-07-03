# Translation Manifest

This document tracks the translation status of all Ourin documentation.

## Status Overview

⚠️ **Re-audited 2026-07-02.** The previous "100% complete / 61 pairs / 0 remaining" summary
was stale and did not match the files on disk. A fresh count of `docs/*_ja-jp.md` /
`docs/*_en-us.md` plus the legacy `DEPENDENCIES` pair found that **20 pairs still contain a
"Translation Pending" placeholder stub** on one side. This manifest now reflects the actual
per-file state, verified by reading each flagged file's content (not just checking that both
files exist).

- **Total tracked pairs**: 57 (56 `_ja-jp` / `_en-us` pairs + 1 `DEPENDENCIES` pair)
- **Complete pairs**: 37
- **Need Translation**: 20 (16 need EN, 4 need JA)
- **Completion**: 37/57 (65%)
- **Notes**: Original unsuffixed working docs (audit reports, plans, summaries) are kept
  in place; their translated counterparts were added alongside rather than renaming them.
  The legacy `DEPENDENCIES.ja.md` / `DEPENDENCIES.en.md` pair was migrated to the standard
  `DEPENDENCIES_ja-jp.md` / `DEPENDENCIES_en-us.md` naming on 2026-07-02 (see
  [TRANSLATION_WORKFLOW.md](TRANSLATION_WORKFLOW.md)); all pairs now use one naming scheme.

## Complete Pairs (37)

1. ✅ About_FMO
2. ✅ AUDIT_PROMPT
3. ✅ BALLOON_1.0M_SPEC
4. ✅ BLOCKER_TRACKER
5. ✅ CODE_SPEC_DIFF_2026-06
6. ✅ COMPAT_FIXES_2026-06
7. ✅ connect_swift
8. ✅ DEPENDENCIES (`DEPENDENCIES_en-us.md` / `DEPENDENCIES_ja-jp.md`)
9. ✅ DevToolsUIMockup
10. ✅ DOCUMENTATION_UPDATE_SUMMARY
11. ✅ GhostConfigurationImplementation
12. ✅ IMPLEMENTATION_PLAN_2026-06
13. ✅ IMPLEMENTATION_STATUS_SUMMARY
14. ✅ INTEGRATION_ROADMAP
15. ✅ NAR_INSTALL_1.0M_SPEC
16. ✅ OURIN_EXTENSIONS
17. ✅ OURIN_MIGRATOR_PLAN
18. ✅ PLUGIN_BRIDGE_COMPLETION_PLAN
19. ✅ PLUGIN_COMPAT_FIX_PROPOSAL
20. ✅ PROJECT_SUMMARY
21. ✅ PROPERTY_1.0M_SPEC
22. ✅ PropertySystem
23. ✅ README
24. ✅ RightClickMenuMockup
25. ✅ SAKURASCRIPT_COMMANDS_SUPPORTED
26. ✅ SAORI_IMPLEMENTATION
27. ✅ SERIKO_IMPLEMENTATION
28. ✅ SERIKO_IMPLEMENTATION_PROGRESS_REPORT
29. ✅ SERIKO_OVERLAY_DRESSUP_RENDERING_SPEC
30. ✅ SHIORI_3.0M_SPEC
31. ✅ SHIORI_EVENTS_FULL_1.0M_PATCHED
32. ✅ SHIORI_EXTERNAL_3.0M_SPEC
33. ✅ SHIORI_RESOURCE_3.0M_SPEC
34. ✅ SSTP_1.xM_SPEC
35. ✅ SSTP_DISPATCHER_GUIDE
36. ✅ SUPPORTED_SAKURA_SCRIPT
37. ✅ YAYA_DIC_COMPAT_IMPLEMENTATION_PLAN

## Documents Needing Translation (20)

Each entry below was verified by opening the file: the listed side still contains the
`**Status:** Translation Pending` (or `**ステータス:** 翻訳待ち`) placeholder stub, not a
real translation.

### Need EN translation (16)

1. ⏳ SPEC_PLUGIN_2.0M (JA → **need EN**)
2. ⏳ OURIN_YAYA_ADAPTER_SPEC_1.0M (JA → **need EN**)
3. ⏳ OURIN_USL_1.0M_SPEC (JA → **need EN**)
4. ⏳ OURIN_SHIORI_EVENTS_3.0M_SPEC (JA → **need EN**)
5. ⏳ SHIORI_EVENTS_3.0M_SPEC (JA → **need EN**)
6. ⏳ PLUGIN_EVENT_2.0M_SPEC (JA → **need EN**)
7. ⏳ PLUGIN_EVENT_2.0M_SPEC_FULL (JA → **need EN**)
8. ⏳ PROPERTY_1.0M_SPEC_FULL (JA → **need EN**)
9. ⏳ PROPERTY_Resource_3.0M_SPEC (JA → **need EN**)
10. ⏳ SAKURASCRIPT_FULL_1.0M_PATCHED (JA → **need EN**)
11. ⏳ HEADLINE_2.0M_SPEC (JA → **need EN**)
12. ⏳ WEB_1.0M_SPEC (JA → **need EN**)
13. ⏳ SSTP_Host_Modules_JA (JA → **need EN**)
14. ⏳ ONBOARDING (JA → **need EN**)
15. ⏳ YAYA_CORE_IMPLEMENTATION_PLAN (JA → **need EN**)
16. ⏳ YAYA_CORE_INVESTIGATION_REPORT (JA → **need EN**)

### Need JA translation (4)

17. ⏳ YAYA_CORE_ARCHITECTURE (EN → **need JA**)
18. ⏳ YAYA_CORE_EXECUTIVE_SUMMARY (EN → **need JA**)
19. ⏳ YAYA_CORE_INDEX (EN → **need JA**)
20. ⏳ YAYA_CORE_TECHNICAL_SPEC (EN → **need JA**)

## Translation Guidelines

### For Technical Specifications
- Keep technical terms (API names, functions, etc.) in English in both versions
- Translate narrative descriptions and explanations
- Maintain consistent terminology across documents

### For Code Examples
- Keep code unchanged
- Translate comments and explanations

### Formatting
- Maintain identical markdown structure
- Keep all anchor links and references consistent
- Ensure TOC/index entries match

## Notes

- All files use the language suffix naming (`_ja-jp.md` or `_en-us.md`); the former
  `DEPENDENCIES.ja.md` / `DEPENDENCIES.en.md` exception was migrated on 2026-07-02.
- Files marked with ✅ are complete with both languages (verified by content, not just
  file existence — a file can exist and still be an unfilled placeholder stub).
- Files marked with ⏳ need translation as indicated; the placeholder side still reads
  "Translation Pending" / "翻訳待ち".
- Priority order in this list reflects importance for end users and developers.
