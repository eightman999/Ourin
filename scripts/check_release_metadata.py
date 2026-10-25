#!/usr/bin/env python3
"""Ourin release metadata consistency check (#99).

Verifies, without Xcode, that the version/OS-floor metadata shipped in the
bundle agrees across every place it is recorded:

  * Ourin/Resources/Info.plist
      - CFBundleShortVersionString  (marketing version, user-facing)
      - CFBundleVersion             (monotonically increasing integer build)
      - LSMinimumSystemVersion      (minimum supported macOS)
      - AppReleaseDate              (ISO date, shown in About)
  * Ourin.xcodeproj/project.pbxproj
      - MACOSX_DEPLOYMENT_TARGET    (all targets must equal the min OS)
      - MARKETING_VERSION           (must equal CFBundleShortVersionString;
                                     used by the XPC service bundle)
      - CURRENT_PROJECT_VERSION     (must equal CFBundleVersion)
  * README.md                     (declared macOS requirement)
  * OurinShioriXPCService/Info.plist (bundle sanity)

Versioning policy (docs/RELEASE_GATES_2026-10-25.md):
  * Pre-1.0 development builds use the legacy 4-component form X.Y.Z.B where
    the last component B MUST equal CFBundleVersion (e.g. 0.0.1.21 / 21).
  * Release builds require CFBundleShortVersionString to contain three
    period-separated integers (MAJOR.MINOR.PATCH). Prerelease labels belong
    in Git tags, not the Apple bundle version. CFBundleVersion stays a plain
    increasing integer.

Usage:
  python3 scripts/check_release_metadata.py [options]

Exit status: 0 = pass (warnings allowed), 1 = at least one failure.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from datetime import date, datetime
from pathlib import Path

BUNDLE_VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
DEV_VERSION_RE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})$")
README_MACOS_RE = re.compile(r"macOS[^\n\d]*(\d+\.\d+)")


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def note(self, msg: str) -> None:
        self.notes.append(msg)

    def render(self) -> str:
        lines = ["== check_release_metadata =="]
        lines += [f"NOTE  {m}" for m in self.notes]
        lines += [f"WARN  {m}" for m in self.warnings]
        lines += [f"FAIL  {m}" for m in self.failures]
        status = "FAIL" if self.failures else "PASS"
        lines.append(f"result: {status} "
                     f"({len(self.failures)} failure(s), {len(self.warnings)} warning(s))")
        return "\n".join(lines)


def load_plist(path: Path, rep: Report) -> dict | None:
    if not path.is_file():
        rep.fail(f"missing plist: {path}")
        return None
    try:
        with path.open("rb") as fh:
            data = plistlib.load(fh)
    except Exception as exc:  # malformed XML/binary
        rep.fail(f"cannot parse {path}: {exc}")
        return None
    if not isinstance(data, dict):
        rep.fail(f"{path} root is not a dict")
        return None
    return data


def check_info_plist(plist: dict, rep: Report, args: argparse.Namespace) -> dict:
    out: dict = {}

    short = plist.get("CFBundleShortVersionString")
    if not isinstance(short, str) or not short:
        rep.fail("CFBundleShortVersionString missing or empty")
    else:
        out["short"] = short
        if BUNDLE_VERSION_RE.fullmatch(short):
            rep.note(f"version '{short}' uses three integer components")
        elif DEV_VERSION_RE.fullmatch(short):
            rep.note(f"version '{short}' uses pre-1.0 dev form X.Y.Z.B")
            if args.release:
                rep.fail(f"--release requires three integer version components, got '{short}'")
        else:
            rep.fail(f"CFBundleShortVersionString '{short}' is neither "
                     "three integer components nor X.Y.Z.B dev form; "
                     "prerelease labels belong in Git tags")

    build = plist.get("CFBundleVersion")
    if not isinstance(build, str) or not build.isdigit() or int(build) <= 0:
        rep.fail(f"CFBundleVersion must be a positive integer, got {build!r}")
    else:
        out["build"] = int(build)
        if args.min_build is not None and int(build) <= args.min_build:
            rep.fail(f"CFBundleVersion {build} is not greater than "
                     f"--min-build {args.min_build}")

    # pre-1.0 convention: last version component == build number
    short_v = out.get("short")
    if short_v and DEV_VERSION_RE.fullmatch(short_v) and "build" in out:
        last = int(short_v.rsplit(".", 1)[1])
        if last != out["build"]:
            rep.fail(f"dev version '{short_v}' last component {last} does not "
                     f"equal CFBundleVersion {out['build']}")

    min_os = plist.get("LSMinimumSystemVersion")
    if min_os != args.min_os:
        rep.fail(f"LSMinimumSystemVersion is {min_os!r}, expected "
                 f"'{args.min_os}'")
    else:
        out["min_os"] = min_os

    rel = plist.get("AppReleaseDate")
    rel_date: date | None = None
    if not isinstance(rel, str) or not DATE_RE.match(rel):
        rep.fail(f"AppReleaseDate missing or not YYYY-MM-DD: {rel!r}")
    else:
        try:
            rel_date = datetime.strptime(rel, "%Y-%m-%d").date()
        except ValueError:
            rep.fail(f"AppReleaseDate is not a real calendar date: {rel}")
    if rel_date is not None:
        today = date.today()
        if rel_date > today:
            rep.fail(f"AppReleaseDate {rel} is in the future")
        age = (today - rel_date).days
        out["release_date"] = rel
        if args.release:
            want = args.release_date or today.isoformat()
            if rel != want:
                rep.fail(f"--release requires AppReleaseDate {want}, got {rel}")
        elif age > args.max_date_age_days:
            rep.warn(f"AppReleaseDate {rel} is {age} days old; "
                     "update it when cutting a release")

    bid = plist.get("CFBundleIdentifier")
    if bid != "furin-lab.Ourin":
        rep.warn(f"CFBundleIdentifier is {bid!r}, expected 'furin-lab.Ourin'")

    return out


def check_pbxproj(text: str, rep: Report, info: dict,
                  args: argparse.Namespace) -> None:
    def values(setting: str) -> list[str]:
        return re.findall(rf"^\s*{re.escape(setting)} = \"?([^\";]+)\"?;",
                          text, re.MULTILINE)

    targets = values("MACOSX_DEPLOYMENT_TARGET")
    if not targets:
        rep.fail("no MACOSX_DEPLOYMENT_TARGET found in project.pbxproj")
    else:
        bad = [v for v in targets if v != args.min_os]
        if bad:
            rep.fail(f"MACOSX_DEPLOYMENT_TARGET mismatch: "
                     f"{sorted(set(targets))} (expected {args.min_os} "
                     f"everywhere, {len(targets)} setting(s))")
        else:
            rep.note(f"all {len(targets)} MACOSX_DEPLOYMENT_TARGET = "
                     f"{args.min_os}")

    short = info.get("short")
    mv = set(values("MARKETING_VERSION"))
    if not mv:
        rep.fail("no MARKETING_VERSION found in project.pbxproj")
    elif short and mv != {short}:
        rep.fail(f"MARKETING_VERSION in pbxproj {sorted(mv)} does not match "
                 f"CFBundleShortVersionString '{short}' "
                 "(XPC bundle version is generated from MARKETING_VERSION)")

    build = info.get("build")
    cpv = set(values("CURRENT_PROJECT_VERSION"))
    if not cpv:
        rep.fail("no CURRENT_PROJECT_VERSION found in project.pbxproj")
    elif build is not None and cpv != {str(build)}:
        rep.fail(f"CURRENT_PROJECT_VERSION in pbxproj {sorted(cpv)} does not "
                 f"match CFBundleVersion {build}")

    # This project records versions explicitly in each bundle target's Debug
    # and Release settings. Checking only the union above would miss a key
    # deleted from just one XPC configuration while the app retains its value.
    settings_blocks = re.findall(
        r"isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\n\s*\};",
        text, re.DOTALL,
    )
    for settings in settings_blocks:
        bundle_id = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;', settings)
        if bundle_id is None:
            continue
        for setting in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
            if not re.search(rf"^\s*{setting} = \"?[^\";]+\"?;", settings, re.MULTILINE):
                rep.fail(f"{bundle_id.group(1)} build configuration missing {setting}")


def check_readme(text: str, rep: Report, args: argparse.Namespace) -> None:
    m = README_MACOS_RE.search(text)
    if not m:
        rep.warn("README.md does not declare a macOS requirement "
                 "(expected e.g. 'macOS 13.0')")
        return
    if m.group(1) != args.min_os:
        rep.fail(f"README declares macOS {m.group(1)} but minimum is "
                 f"{args.min_os}")
    else:
        rep.note(f"README macOS requirement matches {args.min_os}")


def check_xpc_plist(path: Path, rep: Report, info: dict) -> None:
    data = load_plist(path, rep)
    if data is None:
        return
    if data.get("CFBundlePackageType") != "XPC!":
        rep.fail(f"{path}: CFBundlePackageType is not 'XPC!'")
    for key, setting, expected in (
        ("CFBundleShortVersionString", "MARKETING_VERSION", info.get("short")),
        ("CFBundleVersion", "CURRENT_PROJECT_VERSION", info.get("build")),
    ):
        value = data.get(key)
        references = {f"$({setting})", f"${{{setting}}}"}
        if not isinstance(value, str) or (
            value not in references and (expected is None or value != str(expected))
        ):
            rep.fail(f"{path}: {key} must reference {setting} or equal "
                     f"the app value {expected!r}, got {value!r}")
    svc = data.get("XPCService") or {}
    if svc.get("ServiceType") != "Application":
        rep.warn(f"{path}: XPCService.ServiceType is not 'Application'")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=None,
                    help="repository root (default: script's parent dir)")
    ap.add_argument("--min-os", default="13.0",
                    help="expected minimum macOS version (default: 13.0)")
    ap.add_argument("--expect-version", default=None,
                    help="require CFBundleShortVersionString to equal this")
    ap.add_argument("--expect-build", type=int, default=None,
                    help="require CFBundleVersion to equal this")
    ap.add_argument("--min-build", type=int, default=None,
                    help="require CFBundleVersion > N (monotonic bump check)")
    ap.add_argument("--release", action="store_true",
                    help="release mode: three integer version components + AppReleaseDate check")
    ap.add_argument("--release-date", default=None,
                    help="expected AppReleaseDate with --release "
                         "(default: today)")
    ap.add_argument("--max-date-age-days", type=int, default=180,
                    help="warn if AppReleaseDate is older than this many days")
    args = ap.parse_args(argv)

    root = Path(args.root).resolve() if args.root else \
        Path(__file__).resolve().parent.parent
    rep = Report()

    plist = load_plist(root / "Ourin/Resources/Info.plist", rep)
    info: dict = {}
    if plist is not None:
        info = check_info_plist(plist, rep, args)

    if args.expect_version and info.get("short") != args.expect_version:
        rep.fail(f"expected version {args.expect_version}, "
                 f"got {info.get('short')!r}")
    if args.expect_build is not None and info.get("build") != args.expect_build:
        rep.fail(f"expected build {args.expect_build}, "
                 f"got {info.get('build')!r}")

    pbx = root / "Ourin.xcodeproj/project.pbxproj"
    if pbx.is_file():
        check_pbxproj(pbx.read_text(encoding="utf-8"), rep, info, args)
    else:
        rep.fail(f"missing {pbx}")

    readme = root / "README.md"
    if readme.is_file():
        check_readme(readme.read_text(encoding="utf-8", errors="replace"),
                     rep, args)
    else:
        rep.warn("README.md not found; cannot cross-check declared min OS")

    check_xpc_plist(root / "OurinShioriXPCService/Info.plist", rep, info)

    print(rep.render())
    return 1 if rep.failures else 0


if __name__ == "__main__":
    sys.exit(main())
