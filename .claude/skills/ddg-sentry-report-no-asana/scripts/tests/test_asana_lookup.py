"""Unit tests for asana_lookup decision logic (exact-match guard, builder)."""

from __future__ import annotations

import unittest
from typing import Any
from unittest.mock import MagicMock

from .. import asana_lookup


def _task(
    *,
    gid: str = "1",
    name: str = "EXC_CRASH Foo",
    completed: bool = False,
    permalink_url: str = "https://app.asana.com/0/0/1",
    tags: list[dict[str, Any]] | None = None,
    custom_field_gid: str = "1214294661819893",
    custom_field_value: str = "",
) -> dict[str, Any]:
    return {
        "gid": gid,
        "name": name,
        "completed": completed,
        "permalink_url": permalink_url,
        "tags": tags or [],
        "custom_fields": [
            {"gid": custom_field_gid, "display_value": custom_field_value},
        ],
    }


CUSTOM_FIELD_GID = "1214294661819893"


class ExactMatchGuardTests(unittest.TestCase):
    def test_exact_element_match(self) -> None:
        task = _task(custom_field_value="APPLE-MACOS-D6N6,APPLE-MACOS-D7YC")
        self.assertTrue(
            asana_lookup._short_id_is_exact_match(
                task, "APPLE-MACOS-D6N6", CUSTOM_FIELD_GID
            )
        )

    def test_substring_does_not_match(self) -> None:
        # APPLE-MACOS-D6N should not match APPLE-MACOS-D6N6 even though substring.
        task = _task(custom_field_value="APPLE-MACOS-D6N6,APPLE-MACOS-D7YC")
        self.assertFalse(
            asana_lookup._short_id_is_exact_match(task, "APPLE-MACOS-D6N", CUSTOM_FIELD_GID)
        )

    def test_with_whitespace_around_values(self) -> None:
        task = _task(custom_field_value=" APPLE-MACOS-D6N6 , APPLE-MACOS-D7YC ")
        self.assertTrue(
            asana_lookup._short_id_is_exact_match(
                task, "APPLE-MACOS-D7YC", CUSTOM_FIELD_GID
            )
        )

    def test_no_custom_field_returns_false(self) -> None:
        task = {"custom_fields": []}
        self.assertFalse(
            asana_lookup._short_id_is_exact_match(
                task, "APPLE-MACOS-D6N6", CUSTOM_FIELD_GID
            )
        )

    def test_ignores_other_custom_fields(self) -> None:
        task = {
            "custom_fields": [
                {"gid": "9999", "display_value": "APPLE-MACOS-D6N6"},
                {"gid": CUSTOM_FIELD_GID, "display_value": "APPLE-MACOS-OTHER"},
            ],
        }
        self.assertFalse(
            asana_lookup._short_id_is_exact_match(
                task, "APPLE-MACOS-D6N6", CUSTOM_FIELD_GID
            )
        )


class BuildExistingAsanaTaskTests(unittest.TestCase):
    def test_open_task_no_tag(self) -> None:
        task = _task(
            gid="abc",
            name="EXC_CRASH X",
            completed=False,
            permalink_url="https://app.asana.com/0/0/abc",
            tags=[],
            custom_field_value="APPLE-MACOS-D6N6,APPLE-MACOS-D7YC",
        )
        cluster = {"short_ids": ["APPLE-MACOS-D6N6", "APPLE-MACOS-NEW1"]}
        result = asana_lookup._build_existing_asana_task(
            client=MagicMock(),  # unused
            task=task,
            cluster=cluster,
            platform="macos",
            version_display="1.186",
            custom_field_gid=CUSTOM_FIELD_GID,
        )
        self.assertEqual(result["gid"], "abc")
        self.assertEqual(result["status"], "open")
        self.assertIsNone(result["fix_version_tag"])
        self.assertEqual(result["fix_version_compare"], "none")
        self.assertIsNone(result["is_duplicate_link"])
        self.assertEqual(
            result["merged_short_ids"], ["APPLE-MACOS-D6N6", "APPLE-MACOS-D7YC"]
        )
        self.assertEqual(result["needs_short_id_extension"], ["APPLE-MACOS-NEW1"])

    def test_completed_with_future_tag(self) -> None:
        task = _task(
            gid="def",
            completed=True,
            tags=[
                {"name": "macos-app-release-1.188.0"},
                {"name": "macos-app-release-1.187.0"},
            ],
            custom_field_value="APPLE-MACOS-D6N6",
        )
        cluster = {"short_ids": ["APPLE-MACOS-D6N6"]}
        result = asana_lookup._build_existing_asana_task(
            client=MagicMock(),
            task=task,
            cluster=cluster,
            platform="macos",
            version_display="1.186",
            custom_field_gid=CUSTOM_FIELD_GID,
        )
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["fix_version_tag"], "macos-app-release-1.188.0")
        self.assertEqual(result["fix_version_compare"], "gt")
        self.assertEqual(result["needs_short_id_extension"], [])

    def test_completed_with_old_tag_means_regression(self) -> None:
        task = _task(
            completed=True,
            tags=[{"name": "macos-app-release-1.180.0"}],
            custom_field_value="APPLE-MACOS-D6N6",
        )
        cluster = {"short_ids": ["APPLE-MACOS-D6N6"]}
        result = asana_lookup._build_existing_asana_task(
            client=MagicMock(),
            task=task,
            cluster=cluster,
            platform="macos",
            version_display="1.186",
            custom_field_gid=CUSTOM_FIELD_GID,
        )
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["fix_version_compare"], "lte")

    def test_duplicate_task(self) -> None:
        task = _task(gid="dup1", name="[Duplicate] foo")
        cluster = {"short_ids": ["APPLE-MACOS-D6N6"]}
        result = asana_lookup._build_existing_asana_task(
            client=MagicMock(),
            task=task,
            cluster=cluster,
            platform="macos",
            version_display="1.186",
            custom_field_gid=CUSTOM_FIELD_GID,
        )
        # We surface the duplicate gid so the operator can investigate.
        self.assertEqual(result["is_duplicate_link"], "dup1")


if __name__ == "__main__":
    unittest.main()
