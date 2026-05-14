"""Unit tests for asana_file_summary — input parsing + status-subtask picker."""

from __future__ import annotations

import unittest

from .. import asana_file_summary


class ReadInputsTests(unittest.TestCase):
    def test_summary_json_happy(self) -> None:
        data = {
            "schema_version": 1,
            "platform": "macOS",
            "name": "Sentry summary - macOS 1.186 - 2026-05-14",
            "html_notes": "<body>...</body>",
            "is_crash_free_report": False,
            "weekly_release_dri_lookup": {
                "platform_project_gid": "1201037661562251",
                "dri_task_name": "macOS App Weekly Release DRI",
                "weekday_status_keyword": "Thursday status",
            },
        }
        result = asana_file_summary._read_inputs(data)
        self.assertEqual(result["name"], data["name"])
        self.assertEqual(result["html_notes"], data["html_notes"])
        self.assertFalse(result["is_crash_free"])

    def test_analyze_json_crash_free(self) -> None:
        data = {
            "schema_version": 1,
            "platform": "macos",
            "version": "1.187",
            "clusters": [],
            "crash_free": True,
            "summary_name": "Sentry summary - macOS 1.187 - 2026-05-14",
            "crash_free_html_notes": "<body>crash-free</body>",
            "weekly_release_dri_lookup": {
                "platform_project_gid": "1201037661562251",
                "dri_task_name": "macOS App Weekly Release DRI",
                "weekday_status_keyword": "Thursday status",
            },
        }
        result = asana_file_summary._read_inputs(data)
        self.assertEqual(result["name"], "Sentry summary - macOS 1.187 - 2026-05-14")
        self.assertEqual(result["html_notes"], "<body>crash-free</body>")
        self.assertTrue(result["is_crash_free"])

    def test_crash_free_missing_fields(self) -> None:
        data = {
            "schema_version": 1,
            "platform": "macos",
            "version": "1.187",
            "clusters": [],
            "crash_free": True,
            # missing summary_name + crash_free_html_notes
            "weekly_release_dri_lookup": {
                "platform_project_gid": "1",
                "dri_task_name": "x",
            },
        }
        with self.assertRaises(ValueError):
            asana_file_summary._read_inputs(data)

    def test_missing_dri_lookup(self) -> None:
        data = {
            "schema_version": 1,
            "platform": "macOS",
            "name": "x",
            "html_notes": "<body/>",
        }
        with self.assertRaises(ValueError):
            asana_file_summary._read_inputs(data)


class PickStatusSubtaskTests(unittest.TestCase):
    def _dri_task(self, subtasks: list[dict]) -> dict:
        return {"gid": "dri-1", "subtasks": subtasks}

    def test_picks_exact_keyword_match(self) -> None:
        dri = self._dri_task(
            [
                {"gid": "1", "name": "Monday status", "completed": False, "created_at": "2026-05-12T00:00:00Z"},
                {"gid": "2", "name": "Thursday status (May 14)", "completed": False, "created_at": "2026-05-14T00:00:00Z"},
            ]
        )
        result = asana_file_summary._pick_status_subtask(dri, "Thursday status")
        self.assertEqual(result["gid"], "2")

    def test_prefers_incomplete(self) -> None:
        dri = self._dri_task(
            [
                {"gid": "1", "name": "Thursday status (May 7)", "completed": True, "created_at": "2026-05-07T00:00:00Z"},
                {"gid": "2", "name": "Thursday status (May 14)", "completed": False, "created_at": "2026-05-14T00:00:00Z"},
            ]
        )
        result = asana_file_summary._pick_status_subtask(dri, "Thursday status")
        self.assertEqual(result["gid"], "2")

    def test_falls_back_to_completed_when_no_incomplete(self) -> None:
        dri = self._dri_task(
            [
                {"gid": "1", "name": "Thursday status (May 7)", "completed": True, "created_at": "2026-05-07T00:00:00Z"},
                {"gid": "2", "name": "Thursday status (May 14)", "completed": True, "created_at": "2026-05-14T00:00:00Z"},
            ]
        )
        result = asana_file_summary._pick_status_subtask(dri, "Thursday status")
        self.assertEqual(result["gid"], "2")

    def test_case_insensitive(self) -> None:
        dri = self._dri_task(
            [
                {"gid": "1", "name": "THURSDAY STATUS", "completed": False, "created_at": "2026-05-14T00:00:00Z"},
            ]
        )
        result = asana_file_summary._pick_status_subtask(dri, "Thursday status")
        self.assertEqual(result["gid"], "1")

    def test_no_match_raises(self) -> None:
        dri = self._dri_task(
            [
                {"gid": "1", "name": "Monday status", "completed": False, "created_at": "2026-05-12T00:00:00Z"},
            ]
        )
        with self.assertRaises(asana_file_summary.AmbiguousResolution):
            asana_file_summary._pick_status_subtask(dri, "Thursday status")


if __name__ == "__main__":
    unittest.main()
