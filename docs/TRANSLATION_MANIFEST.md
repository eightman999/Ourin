# Translation Manifest

This document tracks the translation status of all Ourin documentation.

## Status Overview

- **Complete Pairs**: 5 documents with both EN and JA versions
- **Need Translation**: 32 documents missing one language version
- **Total Unique Documents**: 37

## Complete Pairs (Both EN and JA exist)

1. ✅ About_FMO (`About_FMO_en-us.md` / `About_FMO_ja-jp.md`)
2. ✅ BALLOON_1.0M_SPEC (`BALLOON_1.0M_SPEC_en-us.md` / `BALLOON_1.0M_SPEC_ja-jp.md`)
3. ✅ DevToolsUIMockup (`DevToolsUIMockup_en-us.md` / `DevToolsUIMockup_ja-jp.md`)
4. ✅ connect_swift (`connect_swift_en-us.md` / `connect_swift_ja-jp.md`)
5. ✅ GhostConfigurationImplementation (`GhostConfigurationImplementation_en-us.md` / `GhostConfigurationImplementation_ja-jp.md`)

## Documents Needing Translation

### Priority 1: Core Specifications (Need EN translation)

1. ⏳ SHIORI_3.0M_SPEC (JA → **need EN**)
2. ⏳ SSTP_1.xM_SPEC (JA → **need EN**)
3. ⏳ SPEC_PLUGIN_2.0M (JA → **need EN**)
4. ⏳ OURIN_YAYA_ADAPTER_SPEC_1.0M (JA → **need EN**)
5. ⏳ OURIN_USL_1.0M_SPEC (JA → **need EN**)
6. ⏳ NAR_INSTALL_1.0M_SPEC (JA → **need EN**)

### Priority 2: Events & Properties (Need EN translation)

7. ⏳ OURIN_SHIORI_EVENTS_3.0M_SPEC (JA → **need EN**)
8. ⏳ SHIORI_EVENTS_3.0M_SPEC (JA → **need EN**)
9. ⏳ PLUGIN_EVENT_2.0M_SPEC (JA → **need EN**)
10. ⏳ PLUGIN_EVENT_2.0M_SPEC_FULL (JA → **need EN**)
11. ⏳ PROPERTY_1.0M_SPEC (JA → **need EN**)
12. ⏳ PROPERTY_1.0M_SPEC_FULL (JA → **need EN**)
13. ⏳ PROPERTY_Resource_3.0M_SPEC (JA → **need EN**)

### Priority 3: SakuraScript & Resources (Mixed priority)

14. ⏳ SAKURASCRIPT_FULL_1.0M_PATCHED (JA → **need EN**)
15. ⏳ SHIORI_EXTERNAL_3.0M_SPEC (JA → **need EN**)
16. ⏳ SHIORI_EVENTS_FULL_1.0M_PATCHED (EN → **need JA**)
17. ⏳ SHIORI_RESOURCE_3.0M_SPEC (EN → **need JA**)
18. ⏳ SAKURASCRIPT_COMMANDS_SUPPORTED (EN → **need JA**)

### Priority 4: Supporting Documents

19. ⏳ HEADLINE_2.0M_SPEC (JA → **need EN**)
20. ⏳ WEB_1.0M_SPEC (JA → **need EN**)
21. ⏳ SSTP_Host_Modules_JA (JA → **need EN**)
22. ⏳ ONBOARDING (JA → **need EN**)
23. ⏳ README (JA → **need EN**)

### Priority 5: YAYA Core Documentation

24. ⏳ YAYA_CORE_ARCHITECTURE (EN → **need JA**)
25. ⏳ YAYA_CORE_EXECUTIVE_SUMMARY (EN → **need JA**)
26. ⏳ YAYA_CORE_INDEX (EN → **need JA**)
27. ⏳ YAYA_CORE_TECHNICAL_SPEC (EN → **need JA**)
28. ⏳ YAYA_CORE_IMPLEMENTATION_PLAN (JA → **need EN**)
29. ⏳ YAYA_CORE_INVESTIGATION_REPORT (JA → **need EN**)

### Priority 6: UI & Design

30. ⏳ PropertySystem (EN → **need JA**)
31. ⏳ RightClickMenuMockup (EN → **need JA**)

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

- All files have been renamed to include language suffix (`_ja-jp.md` or `_en-us.md`)
- Files marked with ✅ are complete with both languages
- Files marked with ⏳ need translation as indicated
- Priority order reflects importance for end users and developers
