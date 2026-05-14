"""Tests for the severity gate (LOW/Pre-existing → no Asana calls) and the
per-cluster short-ID lookup cap. Both are rate-limit-budget defences added
after a real Prefect run blew through Asana's HTTP 429 ceiling.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from .. import asana_lookup


def _cluster(
    cluster_id: str,
    severity: str,
    *,
    short_ids: list[str] | None = None,
    culprit: str = "SomeNamespace.someMethod",
) -> dict[str, Any]:
    return {
        "cluster_id": cluster_id,
        "severity": severity,
        "is_one_event_carve_out": False,
        "culprit": culprit,
        "exception_type": "EXC_CRASH",
        "short_ids": short_ids if short_ids is not None else [f"APPLE-IOS-{cluster_id.upper()}"],
        "users_total": 1,
        "events_total": 1,
        "events_alltime_sum": 1,
        "first_party_frame_count": 3,
        "rca_eligible": True,
        "rca_skip_reason": None,
        "sentry_links": {"issues": [], "stacktrace_url": ""},
        "suspect": None,
        "description_hint": "",
        "existing_asana_task": None,
    }


def _analyze_json(clusters: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "generated_at": "2026-05-14T10:00:00Z",
        "platform": "ios",
        "version": "1.186.*",
        "version_display": "1.186",
        "time_range": "24h",
        "weekday": "Thursday",
        "release_strings": [],
        "platform_section_gid": "1214290879396596",
        "sentry_crash_reports_project_gid": "1214294661819890",
        "sentry_crash_group_custom_field_gid": "1214294661819893",
        "project_filter": 8,
        "sentry_org_slug": "ddg",
        "summary_name": "Sentry summary - iOS 1.186 - 2026-05-14",
        "crash_free": False,
        "crash_free_html_notes": None,
        "totals": {"unresolved_count": len(clusters), "new_in_version_count": 0},
        "sentry_links": {"unresolved_query_url": "", "first_release_query_url": ""},
        "weekly_release_dri_lookup": {},  # absent fields → DRI fetch is skipped
        "clusters": clusters,
    }


def _run_capture(input_data: dict[str, Any]) -> tuple[dict[str, Any], list[Any]]:
    """Run asana_lookup.run against input_data with the AsanaClient mocked out.

    Returns (output_json, list_of_AsanaClient_calls). Any Asana API call is
    a test failure when the severity gate works correctly.
    """
    with tempfile.TemporaryDirectory() as tmp:
        in_path = Path(tmp) / "analyze.json"
        out_path = Path(tmp) / "analyze.augmented.json"
        in_path.write_text(json.dumps(input_data))

        mock_calls: list[tuple[str, dict]] = []

        class FakeClient:
            def __init__(self, *a, **kw):
                pass

            def search_tasks(self, **kw):
                mock_calls.append(("search_tasks", kw))
                return []

            def get_task(self, *a, **kw):
                mock_calls.append(("get_task", {"args": a, "kw": kw}))
                return {}

        with patch.object(asana_lookup, "AsanaClient", FakeClient):
            asana_lookup.run(str(in_path), str(out_path), dry_run=False)

        out_data = json.loads(out_path.read_text())

    return out_data, mock_calls


class SeverityGateTests(unittest.TestCase):
    def test_low_and_preexisting_skip_lookup(self) -> None:
        clusters = [
            _cluster("low-1", "low"),
            _cluster("pre-1", "preexisting"),
            _cluster("low-2", "LOW"),  # uppercase to test case-insensitive matching
        ]
        out, calls = _run_capture(_analyze_json(clusters))

        # No Asana search/get calls should have happened for these clusters.
        self.assertEqual(
            [c for c in calls if c[0] == "search_tasks"],
            [],
            f"expected no search_tasks; got {calls}",
        )

        # Each cluster ends with existing_asana_task=None, related_asana_tasks=[].
        for cluster in out["clusters"]:
            self.assertIsNone(cluster["existing_asana_task"], cluster["cluster_id"])
            self.assertEqual(cluster["related_asana_tasks"], [], cluster["cluster_id"])

    def test_high_medium_trigger_lookups(self) -> None:
        clusters = [_cluster("high-1", "high"), _cluster("med-1", "medium")]
        out, calls = _run_capture(_analyze_json(clusters))

        searches = [c for c in calls if c[0] == "search_tasks"]
        # Each eligible cluster does:
        #   - up to 3 short-ID lookups × 2 sections = 6 calls for existing_asana_task
        #   - 2 culprit-name calls for related_asana_tasks
        # With a single short-ID and no match, that's 2 (short_id) + 2 (culprit) = 4
        # per cluster, so 8 in total.
        self.assertGreater(len(searches), 0, "expected Asana lookups for HIGH/MEDIUM")
        # Sanity check: every cluster has the fields populated.
        for cluster in out["clusters"]:
            self.assertIn("existing_asana_task", cluster)
            self.assertIn("related_asana_tasks", cluster)

    def test_mixed_run_only_searches_eligible(self) -> None:
        clusters = [
            _cluster("high-1", "high"),
            _cluster("low-1", "low"),
            _cluster("med-1", "medium"),
            _cluster("pre-1", "preexisting"),
            _cluster("pre-2", "preexisting"),
        ]
        out, calls = _run_capture(_analyze_json(clusters))

        searches = [c for c in calls if c[0] == "search_tasks"]
        # Only high-1 and med-1 trigger calls. Per the logic in
        # test_high_medium_trigger_lookups, each makes 4 calls, total 8.
        self.assertEqual(
            len(searches),
            8,
            f"expected 8 search calls (2 eligible × 4 each); got {len(searches)}",
        )

        # Skipped clusters carry the schema-consistent null/[] values.
        skipped_ids = {"low-1", "pre-1", "pre-2"}
        for cluster in out["clusters"]:
            if cluster["cluster_id"] in skipped_ids:
                self.assertIsNone(cluster["existing_asana_task"])
                self.assertEqual(cluster["related_asana_tasks"], [])


class ShortIdCapTests(unittest.TestCase):
    def test_only_first_3_short_ids_attempted(self) -> None:
        # A wide cluster with 10 short-IDs should attempt at most 3 of them.
        wide = _cluster(
            "high-wide",
            "high",
            short_ids=[f"APPLE-IOS-X{i:02d}" for i in range(10)],
        )
        out, calls = _run_capture(_analyze_json([wide]))

        # Count the unique short-IDs probed in search_tasks calls.
        searched_short_ids: set[str] = set()
        for name, kw in calls:
            if name != "search_tasks":
                continue
            cf = kw.get("custom_field_contains")
            if cf is not None:
                searched_short_ids.add(cf[1])

        # The cap is 3 short-IDs; each is queried in both platform + fallback
        # sections, so the same short-ID appears twice in calls but the unique
        # count is capped.
        self.assertLessEqual(
            len(searched_short_ids),
            3,
            f"short-ID cap breached: probed {searched_short_ids}",
        )
        # Schema field is still set.
        self.assertIsNone(out["clusters"][0]["existing_asana_task"])


if __name__ == "__main__":
    unittest.main()
