#!/usr/bin/env python3
"""Script #2 — Asana write (create / reopen_append / extend_short_ids).

Reads `rca.json`, performs the appropriate Asana write for each task, and
writes `rca.created.json` with per-task results. Per-task failures are
captured in `results[].error`; the script returns exit 0 even when some
tasks failed (orchestrator inspects the JSON).

Run from CLI:

    python3 -m scripts.asana_write --input rca.json --output rca.created.json

Or programmatically:

    from scripts.asana_write import run
    run(input_path="...", output_path="...")
"""

from __future__ import annotations

import logging
import re
import sys
from pathlib import Path
from typing import Any

from . import _common
from ._asana import AsanaClient, AsanaError

logger = logging.getLogger(__name__)

_BODY_RE = re.compile(r"<body>(?P<inner>.*)</body>", re.DOTALL)


def _body_inner(html_notes: str) -> str:
    """Extract the content between <body>...</body>; raises ValueError otherwise."""
    m = _BODY_RE.search(html_notes)
    if not m:
        raise ValueError(
            "html_notes must be wrapped in <body>...</body> per asana-rich-text rules"
        )
    return m.group("inner")


def _merge_body(existing_html_notes: str, append_only_html_notes: str) -> str:
    """Combine an existing body with an append-only segment, both <body>-wrapped."""
    existing_inner = _body_inner(existing_html_notes)
    append_inner = _body_inner(append_only_html_notes)
    return f"<body>{existing_inner}{append_inner}</body>"


def _do_create(client: AsanaClient, task: dict[str, Any]) -> dict[str, Any]:
    created = client.create_task(
        name=task["name"],
        html_notes=task["html_notes"],
        project_gid=task["project_gid"],
        section_gid=task["section_gid"],
        custom_fields={
            # the custom field GID is shared per file (top-level), not per task
            task["_custom_field_gid"]: task["custom_field_value"],
        },
    )
    return {
        "asana_task_gid": created["gid"],
        "permalink_url": created.get(
            "permalink_url", f"https://app.asana.com/0/0/{created['gid']}"
        ),
    }


def _do_reopen_append(client: AsanaClient, task: dict[str, Any]) -> dict[str, Any]:
    task_gid = task["existing_task_gid"]
    if not task_gid:
        raise AsanaError("reopen_append requires existing_task_gid")

    append_only = task.get("append_only_html_notes")
    if not append_only:
        raise AsanaError("reopen_append requires append_only_html_notes")

    # Step 1: re-open.
    client.update_task(task_gid, completed=False)

    # Step 2: read existing body (need html_notes; tags required by hook).
    existing = client.get_task(task_gid, opt_fields="html_notes,tags,tags.name,permalink_url")
    existing_html = existing.get("html_notes", "") or "<body></body>"
    merged = _merge_body(existing_html, append_only)

    # Step 3: write merged body back.
    updated = client.update_task(task_gid, html_notes=merged)
    return {
        "asana_task_gid": task_gid,
        "permalink_url": updated.get(
            "permalink_url",
            existing.get("permalink_url", f"https://app.asana.com/0/0/{task_gid}"),
        ),
    }


def _do_extend_short_ids(client: AsanaClient, task: dict[str, Any]) -> dict[str, Any]:
    task_gid = task["existing_task_gid"]
    if not task_gid:
        raise AsanaError("extend_short_ids requires existing_task_gid")
    new_value = task["custom_field_value"]
    if not new_value:
        raise AsanaError("extend_short_ids requires non-empty custom_field_value")

    updated = client.update_task(
        task_gid,
        custom_fields={task["_custom_field_gid"]: new_value},
    )
    return {
        "asana_task_gid": task_gid,
        "permalink_url": updated.get(
            "permalink_url", f"https://app.asana.com/0/0/{task_gid}"
        ),
    }


_HANDLERS = {
    "create": _do_create,
    "reopen_append": _do_reopen_append,
    "extend_short_ids": _do_extend_short_ids,
}


def _process_task(
    client: AsanaClient | None,
    task: dict[str, Any],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    """Return one entry for rca.created.json.results."""
    cluster_id = task.get("cluster_id", "<missing>")
    mode = task.get("mode")
    result: dict[str, Any] = {
        "cluster_id": cluster_id,
        "mode_executed": mode,
        "asana_task_gid": None,
        "permalink_url": None,
        "error": None,
    }

    if mode not in _HANDLERS:
        result["mode_executed"] = "failed"
        result["error"] = f"unknown mode: {mode!r}"
        logger.error("cluster=%s: %s", cluster_id, result["error"])
        return result

    if dry_run:
        logger.info("[dry-run] cluster=%s would run mode=%s", cluster_id, mode)
        result["mode_executed"] = "skipped"
        result["error"] = "dry_run"
        return result

    try:
        handler_result = _HANDLERS[mode](client, task)  # type: ignore[arg-type]
        result.update(handler_result)
        logger.info(
            "cluster=%s mode=%s → gid=%s",
            cluster_id,
            mode,
            result["asana_task_gid"],
        )
    except (AsanaError, ValueError) as e:
        result["mode_executed"] = "failed"
        result["error"] = str(e)
        logger.error("cluster=%s mode=%s failed: %s", cluster_id, mode, e)
    return result


def run(input_path: str, output_path: str | None = None, *, dry_run: bool = False) -> str:
    """Read rca.json from `input_path`, write rca.created.json to `output_path`.

    If `output_path` is None, derives it by inserting `.created` before `.json`.
    Returns the absolute output path.
    """
    src = Path(input_path).resolve()
    if output_path is None:
        dst = src.with_name(src.stem + ".created.json")
    else:
        dst = Path(output_path).resolve()

    data = _common.load_json(src)
    _common.validate_schema(data, "rca")

    client = AsanaClient() if not dry_run else None  # type: ignore[assignment]
    custom_field_gid = data["sentry_crash_group_custom_field_gid"]

    tasks = data.get("tasks", []) or []
    logger.info("Processing %d tasks (dry_run=%s)", len(tasks), dry_run)

    results: list[dict[str, Any]] = []
    for task in tasks:
        # Smuggle the custom field GID into each task dict for the handlers.
        task["_custom_field_gid"] = custom_field_gid
        results.append(_process_task(client, task, dry_run=dry_run))

    output = {
        "schema_version": _common.SCHEMA_VERSION,
        "generated_at": _common.now_iso_utc(),
        "results": results,
    }
    _common.dump_json_atomic(dst, output)
    logger.info("Wrote %s", dst)
    return str(dst)


def _main(argv: list[str] | None = None) -> int:
    parser = _common.common_arg_parser("Script #2 — Asana create / reopen / extend")
    parser.add_argument("--input", required=True, help="Path to rca.json")
    parser.add_argument("--output", help="Path to write rca.created.json")
    args = parser.parse_args(argv)
    _common.setup_logging(verbose=args.verbose)

    try:
        out = run(args.input, args.output, dry_run=args.dry_run)
    except (AsanaError, ValueError, FileNotFoundError) as e:
        logger.error("%s", e)
        return 1
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
