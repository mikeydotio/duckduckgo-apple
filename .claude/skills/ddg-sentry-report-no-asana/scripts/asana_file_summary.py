#!/usr/bin/env python3
"""Script #3 — file the Sentry summary subtask under today's DRI status.

Accepts either `summary.json` (regular run) or `analyze.json` with
`crash_free: true` (short-circuit). Both carry the platform's Weekly Release
DRI lookup hint plus the subtask name and body.

Steps:
  1. Resolve the platform's `<Platform> App Weekly Release DRI` task.
  2. Disambiguate: prefer assigned over unassigned; else most-recent created_at.
  3. Find today's `<Weekday> status` subtask. Prefer incomplete.
  4. Create the new subtask under it with the summary's name + html_notes.
  5. Add the DRI's assignee as a follower.

Stop-and-ask on any unresolved ambiguity — prints the available candidates
and exits non-zero.

Run from CLI:

    python3 -m scripts.asana_file_summary --input summary.json

Or programmatically:

    from scripts.asana_file_summary import run
    permalink = run(input_path="...")
"""

from __future__ import annotations

import logging
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from . import _common
from ._asana import AsanaClient, AsanaError

logger = logging.getLogger(__name__)


class AmbiguousResolution(RuntimeError):
    """Raised when DRI / status-subtask resolution cannot pick uniquely."""

    def __init__(self, message: str, candidates: list[dict[str, Any]]):
        super().__init__(message)
        self.candidates = candidates


def _resolve_dri_task(
    client: AsanaClient,
    *,
    platform_project_gid: str,
    dri_task_name: str,
) -> dict[str, Any]:
    """Resolve the platform's Weekly Release DRI task. Raises on ambiguity."""
    results = client.search_tasks(
        projects_any=platform_project_gid,
        text=dri_task_name,
        completed=False,
        opt_fields="name,assignee,assignee.name,created_at,permalink_url",
        limit=20,
    )
    # Asana's text filter is fuzzy — keep only exact-name matches.
    exact = [t for t in results if t.get("name") == dri_task_name]
    if not exact:
        raise AmbiguousResolution(
            f"No open task named exactly {dri_task_name!r} in project {platform_project_gid}",
            results,
        )

    if len(exact) == 1:
        return exact[0]

    assigned = [t for t in exact if t.get("assignee") is not None]
    if len(assigned) == 1:
        return assigned[0]

    pool = assigned if assigned else exact
    pool_sorted = sorted(pool, key=lambda t: t.get("created_at") or "")
    if not pool_sorted:
        raise AmbiguousResolution("Empty DRI task pool after filtering", exact)
    return pool_sorted[-1]


def _today_weekday_keyword(fallback: str | None) -> str:
    """Compute today's `<Weekday> status` keyword (e.g. 'Thursday status').

    If a value was already supplied in the input JSON, prefer that one — the
    skill's `analyze` mode used the system clock at run time, which is the
    authoritative source. Otherwise compute it ourselves.
    """
    if fallback:
        return fallback
    weekday = datetime.now().strftime("%A")
    return f"{weekday} status"


def _pick_status_subtask(
    dri_task: dict[str, Any],
    weekday_keyword: str,
) -> dict[str, Any]:
    """Return the subtask whose name contains `weekday_keyword` (case-insensitive).

    Preference: incomplete over complete; ties broken by most-recent `created_at`.
    """
    subtasks = dri_task.get("subtasks", []) or []
    keyword_lc = weekday_keyword.lower()
    matches = [
        st
        for st in subtasks
        if keyword_lc in (st.get("name") or "").lower()
    ]
    if not matches:
        raise AmbiguousResolution(
            f"No subtask containing {weekday_keyword!r} (case-insensitive) "
            f"under DRI task {dri_task.get('gid')}",
            subtasks,
        )

    incomplete = [st for st in matches if not st.get("completed")]
    pool = incomplete or matches
    pool_sorted = sorted(pool, key=lambda st: st.get("created_at") or "")
    return pool_sorted[-1]


def _read_inputs(data: dict[str, Any]) -> dict[str, Any]:
    """Normalise summary.json vs analyze.json-crash-free into a uniform dict.

    Returns: { name, html_notes, weekly_release_dri_lookup, is_crash_free }
    """
    sv = data.get("schema_version")
    if sv != _common.SCHEMA_VERSION:
        raise ValueError(
            f"unsupported schema_version: {sv!r} (expected {_common.SCHEMA_VERSION})"
        )

    if data.get("crash_free") is True:
        # analyze.json with crash_free short-circuit
        name = data.get("summary_name")
        html_notes = data.get("crash_free_html_notes")
        if not name or not html_notes:
            raise ValueError(
                "crash_free analyze.json missing summary_name or crash_free_html_notes"
            )
        is_crash_free = True
    else:
        # summary.json
        _common.validate_schema(data, "summary")
        name = data["name"]
        html_notes = data["html_notes"]
        is_crash_free = bool(data.get("is_crash_free_report"))

    lookup = data.get("weekly_release_dri_lookup")
    if not lookup or not lookup.get("platform_project_gid") or not lookup.get("dri_task_name"):
        raise ValueError(
            "input JSON missing weekly_release_dri_lookup.{platform_project_gid,dri_task_name}"
        )

    return {
        "name": name,
        "html_notes": html_notes,
        "weekly_release_dri_lookup": lookup,
        "is_crash_free": is_crash_free,
    }


def run(input_path: str, *, dry_run: bool = False) -> str | None:
    """File the Sentry summary subtask under today's DRI status subtask.

    Returns the new subtask's permalink URL on success, or None in dry-run.
    Raises AmbiguousResolution on stop-and-ask conditions.
    """
    src = Path(input_path).resolve()
    data = _common.load_json(src)
    inputs = _read_inputs(data)
    lookup = inputs["weekly_release_dri_lookup"]

    if dry_run:
        logger.info(
            "[dry-run] would file subtask name=%r under %s / today's %s; followers from DRI assignee",
            inputs["name"],
            lookup["dri_task_name"],
            lookup.get("weekday_status_keyword") or "<Weekday> status",
        )
        return None

    client = AsanaClient()

    dri_task = _resolve_dri_task(
        client,
        platform_project_gid=lookup["platform_project_gid"],
        dri_task_name=lookup["dri_task_name"],
    )
    dri_assignee_gid = (dri_task.get("assignee") or {}).get("gid")
    logger.info(
        "DRI task gid=%s assignee=%s",
        dri_task.get("gid"),
        dri_task.get("assignee", {}).get("name") if dri_task.get("assignee") else "<none>",
    )

    # Fetch subtasks (tags,tags.name required by the hook even on parent task fetches).
    dri_with_subtasks = client.get_task(
        dri_task["gid"],
        opt_fields=(
            "subtasks,subtasks.name,subtasks.completed,subtasks.created_at,"
            "subtasks.permalink_url,tags,tags.name"
        ),
    )
    weekday_keyword = _today_weekday_keyword(lookup.get("weekday_status_keyword"))
    status_subtask = _pick_status_subtask(dri_with_subtasks, weekday_keyword)
    logger.info(
        "Status subtask gid=%s name=%r (completed=%s)",
        status_subtask.get("gid"),
        status_subtask.get("name"),
        status_subtask.get("completed"),
    )

    new_subtask = client.create_task(
        parent_gid=status_subtask["gid"],
        name=inputs["name"],
        html_notes=inputs["html_notes"],
    )
    permalink = new_subtask.get(
        "permalink_url", f"https://app.asana.com/0/0/{new_subtask['gid']}"
    )
    logger.info("Created subtask gid=%s url=%s", new_subtask["gid"], permalink)

    if dri_assignee_gid:
        try:
            client.add_followers(new_subtask["gid"], followers=[dri_assignee_gid])
            logger.info("Added DRI %s as follower", dri_assignee_gid)
        except AsanaError as e:
            # Follower-add failure is non-fatal — the subtask is filed.
            logger.warning("add_followers failed (non-fatal): %s", e)
    else:
        logger.info("DRI task has no assignee; skipping follower add")

    return permalink


def _print_candidates(label: str, candidates: list[dict[str, Any]]) -> None:
    print(f"\n  {label}:", file=sys.stderr)
    if not candidates:
        print("    <none>", file=sys.stderr)
        return
    for c in candidates:
        gid = c.get("gid", "?")
        name = c.get("name", "?")
        permalink = c.get("permalink_url", "")
        completed = c.get("completed")
        completed_str = " (completed)" if completed else ""
        print(f"    - {gid}: {name!r}{completed_str}  {permalink}", file=sys.stderr)


def _main(argv: list[str] | None = None) -> int:
    parser = _common.common_arg_parser("Script #3 — file Sentry summary subtask")
    parser.add_argument(
        "--input",
        required=True,
        help="Path to summary.json (or analyze.json when crash_free)",
    )
    args = parser.parse_args(argv)
    _common.setup_logging(verbose=args.verbose)

    try:
        permalink = run(args.input, dry_run=args.dry_run)
    except AmbiguousResolution as e:
        logger.error("%s", e)
        _print_candidates("candidates", e.candidates)
        print("\nResolve the ambiguity (e.g. mark stale duplicates complete) and retry.",
              file=sys.stderr)
        return 2
    except (AsanaError, ValueError, FileNotFoundError) as e:
        logger.error("%s", e)
        return 1

    if permalink:
        print(permalink)
    return 0


if __name__ == "__main__":
    sys.exit(_main())
