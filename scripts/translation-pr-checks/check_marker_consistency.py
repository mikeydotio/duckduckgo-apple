#!/usr/bin/env python3
"""
Markdown Marker Consistency Check

Verifies that markdown bold markers (`**`) in localized strings match the
English source. Smartling occasionally returns translations where the `**`
markers are dropped or unpaired; because our SwiftUI rendering uses
`Text(LocalizedStringKey(...))`, a broken pair renders literal asterisks or
loses the bold styling.

For each key, the number of `**` occurrences in a locale's value is compared to
the English source value. A key/locale is flagged when:
  - the locale's `**` count differs from the English source count, or
  - the locale's `**` count is odd (an unpaired marker), which is always broken.

Modes:
  - Default (PR check): only inspects keys whose value changed vs the base
    branch, so it flags regressions introduced by the PR without choking on the
    pre-existing backlog.
  - --all (audit): scans every string in the platform for a full sweep.

Supports .strings (English from en.lproj) and .xcstrings (String Catalogs).

Usage:
    python3 check_marker_consistency.py --platform iOS
    python3 check_marker_consistency.py --platform macOS --all

Exit code is 1 when any mismatch is found, 0 otherwise.

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import os
import sys
from typing import Dict, List, Tuple

from localization_utils import (
    get_changed_files,
    get_files_content_at_base,
    get_search_paths,
    parse_strings_file,
    parse_xcstrings,
)

MARKER = "**"

# (display_key, file, locale, en_count, loc_count)
Finding = Tuple[str, str, str, int, int]


def count_markers(value: str) -> int:
    """Count non-overlapping `**` occurrences in a string value."""
    return value.count(MARKER) if value else 0


def read_file(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def flatten_localization(entry: Dict) -> Dict[str, str]:
    """Flatten one .xcstrings localization entry to {subpath: value}.

    Handles plain stringUnit values and plural/device variations.
    """
    leaves: Dict[str, str] = {}
    if not isinstance(entry, dict):
        return leaves
    string_unit = entry.get("stringUnit")
    if isinstance(string_unit, dict) and isinstance(string_unit.get("value"), str):
        leaves[""] = string_unit["value"]
    variations = entry.get("variations")
    if isinstance(variations, dict):
        for kind, cases in variations.items():
            if not isinstance(cases, dict):
                continue
            for case_name, case_entry in cases.items():
                for sub_path, value in flatten_localization(case_entry).items():
                    name = f"{kind}.{case_name}"
                    leaves[f"{name}.{sub_path}" if sub_path else name] = value
    return leaves


def compare(en_count: int, loc_count: int) -> bool:
    """True if the locale marker count is a problem vs the English source."""
    return loc_count != en_count or loc_count % 2 != 0


def en_sibling_path(strings_path: str) -> str:
    """en.lproj sibling of a <locale>.lproj/<name>.strings path."""
    parent = os.path.dirname(os.path.dirname(strings_path))
    return os.path.join(parent, "en.lproj", os.path.basename(strings_path))


# =============================================================================
# .strings
# =============================================================================

def check_strings_file(path: str, only_changed_keys=None) -> List[Finding]:
    locale_dir = os.path.basename(os.path.dirname(path))
    if locale_dir in ("en.lproj", "Base.lproj"):
        return []
    en_path = en_sibling_path(path)
    if not os.path.exists(en_path):
        return []
    english = parse_strings_file(read_file(en_path))
    translated = parse_strings_file(read_file(path))
    locale = locale_dir[: -len(".lproj")]
    findings: List[Finding] = []
    for key, value in translated.items():
        if only_changed_keys is not None and key not in only_changed_keys:
            continue
        if key not in english:
            continue
        en_count = count_markers(english[key])
        loc_count = count_markers(value)
        if compare(en_count, loc_count):
            findings.append((key, path, locale, en_count, loc_count))
    return findings


# =============================================================================
# .xcstrings
# =============================================================================

def check_xcstrings_data(new_data: Dict, path: str, old_data: Dict = None) -> List[Finding]:
    source_lang = new_data.get("sourceLanguage", "en")
    findings: List[Finding] = []
    old_strings = (old_data or {}).get("strings", {})
    for key, entry in new_data.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        if not isinstance(localizations, dict):
            continue
        if source_lang in localizations:
            source_leaves = flatten_localization(localizations[source_lang])
        else:
            source_leaves = {"": key}
        old_locs = old_strings.get(key, {}).get("localizations", {}) if old_data is not None else {}
        for locale, loc_entry in localizations.items():
            if locale == source_lang:
                continue
            new_leaves = flatten_localization(loc_entry)
            old_leaves = flatten_localization(old_locs.get(locale, {})) if old_data is not None else {}
            for sub_path, loc_value in new_leaves.items():
                if old_data is not None and old_leaves.get(sub_path) == loc_value:
                    continue
                source_value = source_leaves.get(sub_path, source_leaves.get(""))
                if source_value is None:
                    continue
                en_count = count_markers(source_value)
                loc_count = count_markers(loc_value)
                if compare(en_count, loc_count):
                    display_key = f"{key} [{sub_path}]" if sub_path else key
                    findings.append((display_key, path, locale, en_count, loc_count))
    return findings


# =============================================================================
# Modes
# =============================================================================

def check_changed(platform: str) -> List[Finding]:
    """PR mode: only keys changed vs the base branch."""
    paths = get_search_paths(platform)
    findings: List[Finding] = []

    strings_files = get_changed_files([".strings"], paths)
    base_strings = get_files_content_at_base(strings_files)
    for path in strings_files:
        old = parse_strings_file(base_strings.get(path, ""))
        new = parse_strings_file(read_file(path))
        changed_keys = {k for k, v in new.items() if old.get(k) != v}
        findings.extend(check_strings_file(path, only_changed_keys=changed_keys))

    xcstrings_files = get_changed_files([".xcstrings"], paths)
    base_xc = get_files_content_at_base(xcstrings_files)
    for path in xcstrings_files:
        new_data = parse_xcstrings(read_file(path))
        old_data = parse_xcstrings(base_xc.get(path, ""))
        findings.extend(check_xcstrings_data(new_data, path, old_data=old_data))

    return findings


def check_all(platform: str) -> List[Finding]:
    """Audit mode: every string in the platform."""
    findings: List[Finding] = []
    for root_path in get_search_paths(platform):
        for dirpath, _dirs, filenames in os.walk(root_path):
            if any(skip in dirpath for skip in (".build", "DerivedData", "node_modules")):
                continue
            for filename in filenames:
                full = os.path.join(dirpath, filename)
                if filename.endswith(".strings"):
                    findings.extend(check_strings_file(full))
                elif filename.endswith(".xcstrings"):
                    findings.extend(check_xcstrings_data(parse_xcstrings(read_file(full)), full))
    return findings


def report(findings: List[Finding], mode_label: str) -> int:
    if not findings:
        print("✅ No markdown marker mismatches found.")
        return 0

    def categorize(en_count: int, loc_count: int) -> str:
        if loc_count % 2 != 0:
            return "UNPAIRED"
        if en_count == 0 and loc_count > 0:
            return "ADDED"
        return "DROPPED"

    by_key: Dict[Tuple[str, str, int], List[Tuple[str, int]]] = {}
    for key, path, locale, en_count, loc_count in findings:
        by_key.setdefault((key, path, en_count), []).append((locale, loc_count))

    real_bugs = sum(1 for _k, _p, _l, e, c in findings if categorize(e, c) != "ADDED")
    print(f"⚠️  Found {len(findings)} markdown marker mismatch(es) {mode_label} "
          f"across {len(by_key)} key(s) "
          f"({real_bugs} marker bug(s); "
          f"{len(findings) - real_bugs} likely content mismatch — see ADDED):\n")
    for (key, path, en_count), locales in sorted(by_key.items()):
        print(f"  {key}  ({path})")
        print(f"      English source: {en_count} '**' marker(s)")
        for locale, loc_count in sorted(locales):
            print(f"      {locale}: {loc_count}  [{categorize(en_count, loc_count)}]")
        print()
    print("Each translation's '**' count must match the English source. "
          "Fix the affected translations at the Smartling source.")
    print("Legend: UNPAIRED = odd marker count (always broken); "
          "DROPPED = markers missing/changed vs source; "
          "ADDED = source has none but translation does (usually wrong content).")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Check markdown bold marker consistency.")
    parser.add_argument("--platform", required=True, choices=["iOS", "macOS"])
    parser.add_argument("--all", action="store_true",
                        help="Audit every string instead of only PR changes.")
    args = parser.parse_args()

    if args.all:
        return report(check_all(args.platform), mode_label="in the tree")
    return report(check_changed(args.platform), mode_label="introduced by this PR")


if __name__ == "__main__":
    sys.exit(main())
