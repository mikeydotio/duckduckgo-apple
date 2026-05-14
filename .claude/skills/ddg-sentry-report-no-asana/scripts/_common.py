"""Shared helpers used by all three scripts: JSON I/O + schema validation."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1

# Required top-level keys per file type. Schema-version + a marker field.
_REQUIRED_KEYS: dict[str, tuple[str, ...]] = {
    "analyze": ("schema_version", "platform", "version", "clusters"),
    "analyze.augmented": ("schema_version", "platform", "version", "clusters"),
    "rca": ("schema_version", "platform", "tasks"),
    "rca.created": ("schema_version", "results"),
    "summary": ("schema_version", "platform", "name", "html_notes"),
}


def load_json(path: str | os.PathLike[str]) -> dict[str, Any]:
    """Load a JSON document. Raises FileNotFoundError / ValueError."""
    p = Path(path)
    with p.open("r", encoding="utf-8") as f:
        return json.load(f)


def dump_json_atomic(path: str | os.PathLike[str], data: dict[str, Any]) -> None:
    """Write JSON atomically (tmp file + rename). Parent dir must exist."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        prefix=p.name + ".",
        suffix=".tmp",
        dir=str(p.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp_path, p)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass
        raise


def validate_schema(data: dict[str, Any], file_kind: str) -> None:
    """Ensure schema_version + required keys are present.

    `file_kind` is one of: analyze, analyze.augmented, rca, rca.created, summary.
    Raises ValueError on any mismatch.
    """
    if file_kind not in _REQUIRED_KEYS:
        raise ValueError(f"Unknown file_kind: {file_kind!r}")

    sv = data.get("schema_version")
    if sv != SCHEMA_VERSION:
        raise ValueError(
            f"{file_kind}.json: schema_version={sv!r} not supported "
            f"(expected {SCHEMA_VERSION})"
        )

    required = _REQUIRED_KEYS[file_kind]
    missing = [k for k in required if k not in data]
    if missing:
        raise ValueError(f"{file_kind}.json: missing required keys: {missing}")


def now_iso_utc() -> str:
    """Current UTC time in ISO-8601 with 'Z' suffix and second precision."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
    )


def common_arg_parser(description: str) -> argparse.ArgumentParser:
    """Build an argparse parser pre-populated with --verbose and --dry-run."""
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--verbose", action="store_true", help="DEBUG-level logging")
    p.add_argument("--dry-run", action="store_true", help="Plan but do not call Asana")
    return p


# ---- Asana-tag helpers (pure functions; unit-tested) -----------------------


def parse_fix_version_tag(tag_name: str, platform: str) -> tuple[int, int, int] | None:
    """Return (major, minor, patch) when tag_name is a fix-version tag for `platform`.

    Recognises `<platform>-app-release-X.Y.Z` (e.g. `macos-app-release-1.188.0`).
    Returns None otherwise. `platform` must be lowercase ("ios" | "macos").
    """
    prefix = f"{platform.lower()}-app-release-"
    if not tag_name.startswith(prefix):
        return None
    version_str = tag_name[len(prefix):]
    parts = version_str.split(".")
    if len(parts) != 3:
        return None
    try:
        return tuple(int(x) for x in parts)  # type: ignore[return-value]
    except ValueError:
        return None


def highest_fix_version(
    tags: list[dict[str, Any]],
    platform: str,
) -> tuple[str, tuple[int, int, int]] | None:
    """Pick the highest <platform>-app-release-X.Y.Z tag from a list of tag dicts.

    Each dict must have a `name` field. Returns (tag_name, version_tuple) or None.
    """
    candidates: list[tuple[str, tuple[int, int, int]]] = []
    for tag in tags:
        name = tag.get("name", "")
        version = parse_fix_version_tag(name, platform)
        if version is not None:
            candidates.append((name, version))
    if not candidates:
        return None
    return max(candidates, key=lambda c: c[1])


def parse_version_string(version: str) -> tuple[int, int, int]:
    """Parse a 'X.Y' or 'X.Y.Z' version into (X, Y, Z) with patch defaulting to 0."""
    parts = version.split(".")
    if len(parts) == 2:
        major, minor = int(parts[0]), int(parts[1])
        return (major, minor, 0)
    if len(parts) == 3:
        return (int(parts[0]), int(parts[1]), int(parts[2]))
    raise ValueError(f"Unrecognised version string: {version!r}")


def compare_fix_version(
    fix_version: tuple[int, int, int] | None,
    analysed_version_display: str,
) -> str:
    """Return 'gt' / 'lte' / 'none' per the fix_version_compare contract.

    `analysed_version_display` is the skill's `version_display` (e.g. '1.186').
    Comparison treats a missing patch as `.0` so `1.188 > 1.186.5` correctly.
    Comparison rule: fix_version > analysed → 'gt'; fix_version ≤ analysed → 'lte';
    no fix tag → 'none'.
    """
    if fix_version is None:
        return "none"
    analysed = parse_version_string(analysed_version_display)
    return "gt" if fix_version > analysed else "lte"


def split_custom_field_value(raw: str | None) -> list[str]:
    """Split a comma-separated custom-field value into trimmed non-empty elements."""
    if not raw:
        return []
    return [s.strip() for s in raw.split(",") if s.strip()]


def merge_short_ids(existing: list[str], additions: list[str]) -> list[str]:
    """Return `existing + new additions` preserving order, deduped."""
    seen = set(existing)
    merged = list(existing)
    for short_id in additions:
        if short_id not in seen:
            merged.append(short_id)
            seen.add(short_id)
    return merged
