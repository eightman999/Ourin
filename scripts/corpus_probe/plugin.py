"""Plugin manifest inspection (no untrusted DLL execution)."""
from __future__ import annotations

from pathlib import Path

from .discovery import find_package_root
from .io_util import reject_symlink, resolve_under_root

WINDOWS_MODULE_SUFFIXES = (".dll", ".ocx", ".exe")

# Contract references: Ourin/PluginHost/PluginRegistry.swift readMetaDictionary,
# nativePluginModules, readInstallManifest.


def _is_native_bundle(directory: Path) -> bool:
    for pattern in ("*.plugin", "*.bundle"):
        if any(directory.glob(pattern)):
            return True
    plugins = directory / "Plugins"
    if plugins.is_dir() and any(plugins.glob("*.bundle")):
        return True
    return False


def _resolve_module_path(plugin_root: Path, filename: str) -> tuple[Path | None, str | None]:
    normalized = filename.replace("\\", "/").strip()
    if not normalized or normalized.startswith("/") or ".." in normalized.split("/"):
        return None, "path_traversal_rejected"
    module_path = plugin_root / normalized
    if reject_symlink(module_path):
        return None, "module_symlink"
    resolved = resolve_under_root(plugin_root, module_path)
    if resolved is None:
        return None, "path_traversal_rejected"
    return resolved, None


def probe_plugin(root: Path, probe_id: str) -> dict:
    plugin_root, descript, locate_err = find_package_root(root, "plugin")
    if locate_err or not plugin_root or not descript:
        return _plugin_result(probe_id, "error", locate_err or "plugin_descript_missing", {})

    name = (descript.get("name") or "").strip()
    plugin_id = (descript.get("id") or "").strip()
    filename = (descript.get("filename") or descript.get("dllname") or "").strip()
    if not name or not plugin_id or not filename:
        return _plugin_result(
            probe_id,
            "error",
            "plugin_metadata_incomplete",
            {"structure": {"required_keys_present": False}},
        )

    module_path, path_err = _resolve_module_path(plugin_root, filename)
    if path_err:
        return _plugin_result(probe_id, "error", path_err, {})

    is_windows_module = module_path.suffix.lower() in WINDOWS_MODULE_SUFFIXES if module_path else True
    native_bundle = _is_native_bundle(plugin_root)
    install_manifest = (plugin_root / "install.txt").is_file()

    checks = {
        "structure": {
            "plugin_id_length": len(plugin_id),
            "name_length": len(name),
            "filename_suffix": module_path.suffix.lower() if module_path else "none",
            "install_manifest": install_manifest,
        },
        "manifest": {
            "charset_declared": bool((descript.get("charset") or "").strip()),
            "menu_key_count": sum(1 for key in descript if key.startswith("menu.")),
        },
        "execution": {
            "state": "native_bundle_present" if native_bundle else "metadata_only",
            "can_dispatch_requests": False,
            "runtime_verified": False,
            "windows_module_only": is_windows_module and not native_bundle,
            "native_bundle_present": native_bundle,
        },
    }

    if is_windows_module and not native_bundle:
        return _plugin_result(probe_id, "unsupported", "windows_plugin_not_executable_on_macos", checks)
    if native_bundle:
        return _plugin_result(probe_id, "partial", "native_bundle_present_runtime_not_probed", checks)
    return _plugin_result(probe_id, "partial", "manifest_only_no_runtime_verification", checks)


def _plugin_result(probe_id: str, status: str, reason: str, checks: dict) -> dict:
    return {"id": probe_id, "kind": "plugin", "status": status, "reason": reason, "checks": checks}
