"""Unit tests for asana_write — body-merge logic and per-task dispatch."""

from __future__ import annotations

import unittest

from .. import asana_write


class BodyMergeTests(unittest.TestCase):
    def test_merges_two_bodies(self) -> None:
        existing = "<body>old content</body>"
        append = "<body><hr/>regression note</body>"
        merged = asana_write._merge_body(existing, append)
        self.assertEqual(merged, "<body>old content<hr/>regression note</body>")

    def test_extracts_multiline(self) -> None:
        existing = "<body>\nfirst\n</body>"
        append = "<body><h2>x</h2></body>"
        merged = asana_write._merge_body(existing, append)
        self.assertEqual(merged, "<body>\nfirst\n<h2>x</h2></body>")

    def test_missing_body_wrapping_raises(self) -> None:
        with self.assertRaises(ValueError):
            asana_write._merge_body("plain string", "<body>x</body>")
        with self.assertRaises(ValueError):
            asana_write._merge_body("<body>x</body>", "plain string")


class ProcessTaskUnknownModeTests(unittest.TestCase):
    def test_unknown_mode_records_failure(self) -> None:
        task = {"cluster_id": "x", "mode": "bogus"}
        result = asana_write._process_task(None, task, dry_run=False)
        self.assertEqual(result["mode_executed"], "failed")
        self.assertIn("unknown mode", result["error"])
        self.assertIsNone(result["asana_task_gid"])

    def test_dry_run_records_skipped(self) -> None:
        task = {"cluster_id": "x", "mode": "create"}
        result = asana_write._process_task(None, task, dry_run=True)
        self.assertEqual(result["mode_executed"], "skipped")
        self.assertEqual(result["error"], "dry_run")


if __name__ == "__main__":
    unittest.main()
