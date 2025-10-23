# Ourin (桜鈴) Documentation Index

This directory contains all specifications and documentation for Ourin.

## 📖 How to View

- **Markdown Version**: View `.md` files directly in this directory
- **HTML Version**: View HTML files in the `html/` directory (select from the [index page](html/index.html))

## 🎯 Getting Started

- [ONBOARDING.md](ONBOARDING_en-us.md) - Ourin overview and getting started guide

## 📚 Core Specifications (macOS Version)

These specifications include current implementation status.

### SHIORI System
- [SHIORI/3.0M Specification](SHIORI_3.0M_SPEC_en-us.md) 🟡 **Partial** - macOS native implementation of SHIORI protocol
  - Implemented with YAYA backend
  - C ABI Bundle/Plugin loading not yet implemented

### SSTP Protocol
- [SSTP/1.xM Specification](SSTP_1.xM_SPEC_en-us.md) 🟢 **Implemented** - macOS version of SSTP protocol
  - TCP/HTTP/XPC server implemented
  - Basic SEND/NOTIFY/COMMUNICATE/EXECUTE methods supported

### Plugin System
- [PLUGIN/2.0M Specification](SPEC_PLUGIN_2.0M_en-us.md) 🟡 **Partial** - macOS version of plugin system
  - Plugin detection and loading mechanism implemented
  - Full PLUGIN/2.0M protocol not yet implemented

### NAR Installation
- [NAR INSTALL/1.0M Specification](NAR_INSTALL_1.0M_SPEC_en-us.md) 🟢 **Implemented** - NAR package installation specification
  - Double-click/Drag-and-drop installation supported
  - Basic extraction and error handling implemented

## ⚙️ System Implementation Specifications

### FMO (Shared Memory)
- [About FMO](About_FMO_en-us.md) 🟢 **Complete** - Inter-process shared memory implementation
  - Fully implemented with POSIX shared memory and semaphores
  - Compliant with ninix specification for startup detection

### YAYA System
- [YAYA Adapter Specification 1.0M](OURIN_YAYA_ADAPTER_SPEC_1.0M_en-us.md) 🟢 **Complete** - YAYA ghost execution adapter
  - IPC with helper process implemented
  - `yaya.txt` and `.dic` file parsing supported
  - SHIORI/3.0M bridge implemented

### USL (Loader)
- [USL Specification 1.0M](OURIN_USL_1.0M_SPEC_en-us.md) 🟢 **Implemented** - Universal SHIORI Loader
  - YAYA backend selection mechanism implemented

### Event System
- [SHIORI Events 3.0M Specification](OURIN_SHIORI_EVENTS_3.0M_SPEC_en-us.md) 🟡 **Partial** - System event and SHIORI integration
  - Major events implemented (time, OS state, network, input, D&D)
  - Some events not implemented (headlines, mail BIFF, voice recognition, etc.)

- [Plugin Event 2.0M Specification](PLUGIN_EVENT_2.0M_SPEC_en-us.md) 🟡 **Partial** - Plugin event system
  - Core dispatcher implemented
  - Individual event handlers not implemented

## 🎨 Display & UI Specifications

- [BALLOON/1.0M Specification](BALLOON_1.0M_SPEC_en-us.md) - Balloon (speech bubble) system specification
- [SakuraScript Full Specification 1.0M](SAKURASCRIPT_FULL_1.0M_PATCHED_en-us.md) - Complete SakuraScript command reference
- [SakuraScript Supported Commands](SAKURASCRIPT_COMMANDS_SUPPORTED_en-us.md) - List of implemented and unimplemented commands

## 🔧 Developer Resources

- [DevTools UI Mockup (Japanese)](DevToolsUIMockup_ja-jp.md) - Developer tools UI design
- [DevTools UI Mockup (English)](DevToolsUIMockup_en-us.md) - Developer tools UI mockup
- [Swift Integration Guide](connect_swift_en-us.md) - How to integrate with Swift
- [Property System Implementation](PropertySystem_en-us.md) - Property system implementation details
- [Ghost Configuration Implementation](GhostConfigurationImplementation_en-us.md) - Ghost configuration implementation

## 📖 Detailed Specifications

### SHIORI Related
- [SHIORI Events 3.0M Specification](SHIORI_EVENTS_3.0M_SPEC_en-us.md) - Detailed SHIORI event specification
- [SHIORI Events FULL 1.0M](SHIORI_EVENTS_FULL_1.0M_PATCHED_en-us.md) - Complete SHIORI events
- [SHIORI Resource 3.0M Specification](SHIORI_RESOURCE_3.0M_SPEC_en-us.md) - SHIORI resource management specification
- [SHIORI External 3.0M Specification](SHIORI_EXTERNAL_3.0M_SPEC_en-us.md) - External SHIORI integration specification

### Property System
- [PROPERTY/1.0M Specification](PROPERTY_1.0M_SPEC_en-us.md) - Property system specification
- [PROPERTY/1.0M Full](PROPERTY_1.0M_SPEC_FULL_en-us.md) - Complete property system specification
- [PROPERTY Resource 3.0M Specification](PROPERTY_Resource_3.0M_SPEC_en-us.md) - Property resource specification

### Plugins
- [Plugin Event 2.0M Full](PLUGIN_EVENT_2.0M_SPEC_FULL_en-us.md) - Complete plugin event specification

### Other Systems
- [HEADLINE/2.0M Specification](HEADLINE_2.0M_SPEC_en-us.md) - Headline system specification
- [WEB/1.0M Specification](WEB_1.0M_SPEC_en-us.md) - Web functionality specification
- [SSTP Host Modules (Japanese)](SSTP_Host_Modules_JA_ja-jp.md) - SSTP host module description

## 📖 YAYA Core Documentation

YAYA Core is developed in a separate repository, but reference materials are included in this directory.

- [YAYA Core Executive Summary](YAYA_CORE_EXECUTIVE_SUMMARY_en-us.md) - YAYA Core overview and direction
- [YAYA Core Technical Specification](YAYA_CORE_TECHNICAL_SPEC_en-us.md) - YAYA Core technical details
- [YAYA Core Architecture](YAYA_CORE_ARCHITECTURE_en-us.md) - YAYA Core design and architecture
- [YAYA Core Implementation Plan](YAYA_CORE_IMPLEMENTATION_PLAN_en-us.md) - YAYA Core implementation plan
- [YAYA Core Investigation Report](YAYA_CORE_INVESTIGATION_REPORT_en-us.md) - YAYA Core investigation report
- [YAYA Core Index](YAYA_CORE_INDEX_en-us.md) - YAYA Core documentation index

## 📋 UI Mockups

- [Right Click Menu Mockup](RightClickMenuMockup_en-us.md) - Right-click menu design

## 🎨 Implementation Status Legend

In the specifications, implementation status uses the following symbols:

- 🟢 **Complete** - Feature fully implemented and verified
- 🟡 **Partial** - Basic functionality implemented, some features missing
- 🔵 **Planned** - Specification finalized but not yet implemented
- `[x]` - Implemented
- `[ ]` - Not implemented
- `✅` - Verified

## 📝 Documentation Update History

- **2025-10-23**: Complete bilingual structure established, all documents translated
- **2025-10-20**: Added implementation status sections to specifications, generated HTML versions
- **2025-07-28**: Initial documentation created

## 🔗 Related Links

- [GitHub Repository](https://github.com/eightman999/Ourin)
- [Project README](../README.md)
- [HTML Documentation Index](html/index.html)

## 📄 License

Documentation follows the Ourin project license (CC BY-NC-SA 4.0).
