#!/usr/bin/env python3
"""
Translation Markdown Marker Checker

Verifies that markdown bold markers (`**`) in localized strings match the
English source. Smartling occasionally returns translations where the `**`
markers are dropped or unpaired; because our SwiftUI rendering uses
`Text(LocalizedStringKey(...))`, a broken pair renders literal asterisks or
loses the bold styling.

The check compares, per key, the number of `**` occurrences in each locale's
value against the English source value. It flags a key/locale when:
  - the locale's `**` count differs from the English source count, or
  - the locale's `**` count is odd (an unpaired marker), which is always broken.

Two modes:
  - Audit (default): scans the whole repository (or the given paths) and
    reports every mismatch. Use this for a full sweep of the backlog.
  - Gate (--changed-only): only inspects keys whose value changed in the
    current working tree vs HEAD. Use this in the Smartling import flow so it
    flags marker regressions *introduced by this import* without choking on the
    pre-existing backlog.

Supports two layouts:
  - Legacy `.strings`: English source is `<root>/en.lproj/<file>.strings`,
    translations are `<root>/<locale>.lproj/<file>.strings`.
  - String Catalogs `.xcstrings`: source language and all localizations live
    inside one JSON file.

Usage:
    check_translation_markers.py [paths...]      # full audit
    check_translation_markers.py --changed-only  # incremental gate

Exit code is 1 when any mismatch is found, 0 otherwise.

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import json
import os
import subprocess
import sys

MARKER = "**"


def count_markers(value):
    """Count non-overlapping `**` occurrences in a string value."""
    return value.count(MARKER) if value else 0


def parse_strings_content(content):
    """Parse .strings file content into {key: value} using plutil."""
    if not content:
        return {}
    try:
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", "-"],
            input=content, capture_output=True, text=True, check=False
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return {k: v for k, v in data.items() if isinstance(v, str)}
    except (json.JSONDecodeError, OSError):
        pass
    return {}


def parse_strings_file(path):
    """Parse a .strings file from disk into {key: value}."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return parse_strings_content(handle.read())
    except OSError:
        return {}


def parse_xcstrings_content(content):
    """Parse .xcstrings JSON content; returns {} on failure."""
    try:
        return json.loads(content) if content else {}
    except json.JSONDecodeError:
        return {}


def head_content(path):
    """Return the committed (HEAD) content of a file, or '' if absent."""
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"],
        capture_output=True, text=True, check=False
    )
    return result.stdout if result.returncode == 0 else ""


def get_changed_translation_files():
    """Return changed .strings / .xcstrings files (working tree + staged)."""
    files = set()
    for args in (["git", "diff", "--name-only", "--", "*.strings", "*.xcstrings"],
                 ["git", "diff", "--cached", "--name-only", "--", "*.strings", "*.xcstrings"]):
        result = subprocess.run(args, capture_output=True, text=True, check=False)
        files.update(f for f in result.stdout.strip().split("\n") if f)
    return sorted(files)


def flatten_localization(entry):
    """Flatten one .xcstrings localization entry to {subpath: value}.

    Handles plain stringUnit values and plural/device variations.
    """
    leaves = {}
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
                    key = f"{kind}.{case_name}"
                    leaves[f"{key}.{sub_path}" if sub_path else key] = value
    return leaves


def xcstrings_findings(data, changed_only_against=None):
    """Yield (display_key, locale, en_count, loc_count) for an xcstrings dict.

    If changed_only_against is a parsed HEAD dict, only report leaves whose
    value differs from HEAD.
    """
    source_lang = data.get("sourceLanguage", "en")
    findings = []
    head_strings = (changed_only_against or {}).get("strings", {})
    for key, entry in data.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        if not isinstance(localizations, dict):
            continue
        if source_lang in localizations:
            source_leaves = flatten_localization(localizations[source_lang])
        else:
            source_leaves = {"": key}

        head_locs = head_strings.get(key, {}).get("localizations", {}) \
            if changed_only_against is not None else {}

        for locale, loc_entry in localizations.items():
            if locale == source_lang:
                continue
            loc_leaves = flatten_localization(loc_entry)
            head_leaves = flatten_localization(head_locs.get(locale, {})) \
                if changed_only_against is not None else {}
            for sub_path, loc_value in loc_leaves.items():
                if changed_only_against is not None and head_leaves.get(sub_path) == loc_value:
                    continue
                source_value = source_leaves.get(sub_path, source_leaves.get(""))
                if source_value is None:
                    continue
                en_count = count_markers(source_value)
                loc_count = count_markers(loc_value)
                if loc_count != en_count or loc_count % 2 != 0:
                    display_key = f"{key} [{sub_path}]" if sub_path else key
                    findings.append((display_key, locale, en_count, loc_count))
    return findings


def check_strings_root(en_dir):
    """Audit all .strings files in an en.lproj dir against sibling locales."""
    findings = []
    parent = os.path.dirname(en_dir)
    sibling_locales = [
        d for d in os.listdir(parent)
        if d.endswith(".lproj") and d not in ("en.lproj", "Base.lproj")
    ]
    for filename in sorted(os.listdir(en_dir)):
        if not filename.endswith(".strings"):
            continue
        en_counts = {k: count_markers(v)
                     for k, v in parse_strings_file(os.path.join(en_dir, filename)).items()}
        for locale_dir in sorted(sibling_locales):
            locale = locale_dir[: -len(".lproj")]
            loc_path = os.path.join(parent, locale_dir, filename)
            if not os.path.exists(loc_path):
                continue
            for key, loc_value in parse_strings_file(loc_path).items():
                if key not in en_counts:
                    continue
                loc_count = count_markers(loc_value)
                if loc_count != en_counts[key] or loc_count % 2 != 0:
                    rel = os.path.relpath(loc_path)
                    findings.append((f"{key}  ({rel})", locale, en_counts[key], loc_count))
    return findings


def check_xcstrings_file(path):
    """Audit a whole .xcstrings catalog."""
    data = parse_xcstrings_content(_read(path))
    rel = os.path.relpath(path)
    return [(f"{k}  ({rel})", loc, e, c) for k, loc, e, c in xcstrings_findings(data)]


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def discover(paths):
    """Return (en_dirs, xcstrings_files) under the given paths."""
    en_dirs, xcstrings = set(), set()
    for root_path in paths:
        if os.path.isfile(root_path) and root_path.endswith(".xcstrings"):
            xcstrings.add(root_path)
            continue
        for dirpath, _dirnames, filenames in os.walk(root_path):
            if ".build" in dirpath or "DerivedData" in dirpath or "node_modules" in dirpath:
                continue
            if os.path.basename(dirpath) == "en.lproj":
                en_dirs.add(dirpath)
            for filename in filenames:
                if filename.endswith(".xcstrings"):
                    xcstrings.add(os.path.join(dirpath, filename))
    return sorted(en_dirs), sorted(xcstrings)


def audit(paths):
    """Full-tree audit. Returns a list of findings."""
    en_dirs, xcstrings_files = discover(paths)
    findings = []
    for en_dir in en_dirs:
        findings.extend(check_strings_root(en_dir))
    for xc_file in xcstrings_files:
        findings.extend(check_xcstrings_file(xc_file))
    return findings


def gate_changed_only():
    """Incremental check over working-tree changes vs HEAD."""
    findings = []
    for path in get_changed_translation_files():
        if path.endswith(".strings"):
            locale_dir = os.path.basename(os.path.dirname(path))
            if locale_dir in ("en.lproj", "Base.lproj"):
                continue
            en_path = os.path.join(
                os.path.dirname(os.path.dirname(path)), "en.lproj", os.path.basename(path))
            if not os.path.exists(en_path):
                continue
            english = parse_strings_file(en_path)
            working = parse_strings_file(path)
            head = parse_strings_content(head_content(path))
            locale = locale_dir[: -len(".lproj")]
            for key, value in working.items():
                if head.get(key) == value or key not in english:
                    continue
                en_count = count_markers(english[key])
                loc_count = count_markers(value)
                if loc_count != en_count or loc_count % 2 != 0:
                    findings.append((f"{key}  ({path})", locale, en_count, loc_count))
        elif path.endswith(".xcstrings"):
            working = parse_xcstrings_content(_read(path))
            head = parse_xcstrings_content(head_content(path))
            for key, loc, en_count, loc_count in xcstrings_findings(working, changed_only_against=head):
                findings.append((f"{key}  ({path})", loc, en_count, loc_count))
    return findings


def report(findings, gate_mode):
    """Print findings grouped by key. Returns process exit code."""
    if not findings:
        print("✅ No markdown marker mismatches found.")
        return 0

    def categorize(en_count, loc_count):
        if loc_count % 2 != 0:
            return "UNPAIRED"
        if en_count == 0 and loc_count > 0:
            return "ADDED"
        return "DROPPED"

    by_key = {}
    for key, locale, en_count, loc_count in findings:
        by_key.setdefault((key, en_count), []).append((locale, loc_count))

    scope = "introduced by this change" if gate_mode else "in the tree"
    real_bugs = sum(1 for _, _l, e, c in findings if categorize(e, c) != "ADDED")
    print(f"⚠️  Found {len(findings)} marker mismatch(es) {scope} across "
          f"{len(by_key)} key(s) "
          f"({real_bugs} marker bug(s); "
          f"{len(findings) - real_bugs} likely content mismatch — see ADDED):\n")
    for (key, en_count), locales in sorted(by_key.items()):
        print(f"  {key}")
        print(f"      English source: {en_count} '**' marker(s)")
        for locale, loc_count in sorted(locales):
            print(f"      {locale}: {loc_count}  [{categorize(en_count, loc_count)}]")
        print()
    print("Legend: UNPAIRED = odd marker count (always broken); "
          "DROPPED = markers missing/changed vs source; "
          "ADDED = source has none but translation does (usually wrong content).")
    return 1


def main():
    args = sys.argv[1:]
    if "--changed-only" in args:
        return report(gate_changed_only(), gate_mode=True)

    paths = [a for a in args if not a.startswith("-")] or ["iOS", "macOS", "SharedPackages"]
    paths = [p for p in paths if os.path.exists(p)]
    return report(audit(paths), gate_mode=False)


if __name__ == "__main__":
    sys.exit(main())
