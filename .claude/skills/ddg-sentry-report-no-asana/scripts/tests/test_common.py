"""Unit tests for pure helper functions in _common.py."""

from __future__ import annotations

import unittest

from .. import _common


class ParseFixVersionTagTests(unittest.TestCase):
    def test_macos_tag(self) -> None:
        self.assertEqual(
            _common.parse_fix_version_tag("macos-app-release-1.188.0", "macos"),
            (1, 188, 0),
        )

    def test_ios_tag(self) -> None:
        self.assertEqual(
            _common.parse_fix_version_tag("ios-app-release-7.220.3", "ios"),
            (7, 220, 3),
        )

    def test_wrong_platform_returns_none(self) -> None:
        self.assertIsNone(
            _common.parse_fix_version_tag("macos-app-release-1.188.0", "ios")
        )

    def test_unrelated_tag_returns_none(self) -> None:
        self.assertIsNone(_common.parse_fix_version_tag("blocked", "macos"))

    def test_malformed_version_returns_none(self) -> None:
        self.assertIsNone(
            _common.parse_fix_version_tag("macos-app-release-1.188", "macos")
        )
        self.assertIsNone(
            _common.parse_fix_version_tag("macos-app-release-1.188.x", "macos")
        )

    def test_uppercase_platform_param(self) -> None:
        # parse_fix_version_tag lowercases the platform.
        self.assertEqual(
            _common.parse_fix_version_tag("macos-app-release-1.188.0", "MACOS"),
            (1, 188, 0),
        )


class HighestFixVersionTests(unittest.TestCase):
    def test_picks_highest_of_two(self) -> None:
        tags = [
            {"name": "macos-app-release-1.187.0"},
            {"name": "macos-app-release-1.189.1"},
            {"name": "macos-app-release-1.188.0"},
        ]
        result = _common.highest_fix_version(tags, "macos")
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result[0], "macos-app-release-1.189.1")
        self.assertEqual(result[1], (1, 189, 1))

    def test_ignores_unrelated_tags(self) -> None:
        tags = [
            {"name": "blocked"},
            {"name": "macos-app-release-1.188.0"},
            {"name": "ios-app-release-7.220.0"},  # wrong platform
        ]
        result = _common.highest_fix_version(tags, "macos")
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result[1], (1, 188, 0))

    def test_no_tags_returns_none(self) -> None:
        self.assertIsNone(_common.highest_fix_version([], "macos"))

    def test_only_unrelated_returns_none(self) -> None:
        tags = [{"name": "blocked"}, {"name": "in-progress"}]
        self.assertIsNone(_common.highest_fix_version(tags, "macos"))


class CompareFixVersionTests(unittest.TestCase):
    def test_fix_greater_than_analysed(self) -> None:
        self.assertEqual(
            _common.compare_fix_version((1, 188, 0), "1.186"),
            "gt",
        )

    def test_fix_equal_to_analysed_is_lte(self) -> None:
        self.assertEqual(
            _common.compare_fix_version((1, 186, 0), "1.186"),
            "lte",
        )

    def test_fix_less_than_analysed_is_lte(self) -> None:
        self.assertEqual(
            _common.compare_fix_version((1, 185, 5), "1.186"),
            "lte",
        )

    def test_three_part_analysed(self) -> None:
        self.assertEqual(
            _common.compare_fix_version((1, 186, 0), "1.186.0"),
            "lte",
        )
        self.assertEqual(
            _common.compare_fix_version((1, 186, 1), "1.186.0"),
            "gt",
        )

    def test_none_fix_returns_none_string(self) -> None:
        self.assertEqual(_common.compare_fix_version(None, "1.186"), "none")


class SplitCustomFieldValueTests(unittest.TestCase):
    def test_single_value(self) -> None:
        self.assertEqual(
            _common.split_custom_field_value("APPLE-MACOS-D6N6"),
            ["APPLE-MACOS-D6N6"],
        )

    def test_multiple_values(self) -> None:
        self.assertEqual(
            _common.split_custom_field_value("APPLE-MACOS-D6N6,APPLE-MACOS-D7YC"),
            ["APPLE-MACOS-D6N6", "APPLE-MACOS-D7YC"],
        )

    def test_whitespace_trimmed(self) -> None:
        self.assertEqual(
            _common.split_custom_field_value(" APPLE-MACOS-D6N6 , APPLE-MACOS-D7YC "),
            ["APPLE-MACOS-D6N6", "APPLE-MACOS-D7YC"],
        )

    def test_empty_inputs(self) -> None:
        self.assertEqual(_common.split_custom_field_value(""), [])
        self.assertEqual(_common.split_custom_field_value(None), [])
        self.assertEqual(_common.split_custom_field_value(",,"), [])


class MergeShortIdsTests(unittest.TestCase):
    def test_adds_missing(self) -> None:
        result = _common.merge_short_ids(["A", "B"], ["C"])
        self.assertEqual(result, ["A", "B", "C"])

    def test_dedups(self) -> None:
        result = _common.merge_short_ids(["A", "B"], ["B", "C", "A", "D"])
        self.assertEqual(result, ["A", "B", "C", "D"])

    def test_preserves_existing_order(self) -> None:
        result = _common.merge_short_ids(["Z", "A", "M"], ["M", "B"])
        self.assertEqual(result, ["Z", "A", "M", "B"])

    def test_empty_additions(self) -> None:
        self.assertEqual(_common.merge_short_ids(["A", "B"], []), ["A", "B"])

    def test_empty_existing(self) -> None:
        self.assertEqual(_common.merge_short_ids([], ["A", "B"]), ["A", "B"])


class ValidateSchemaTests(unittest.TestCase):
    def test_happy_path(self) -> None:
        _common.validate_schema(
            {
                "schema_version": 1,
                "platform": "macos",
                "version": "1.186.*",
                "clusters": [],
            },
            "analyze",
        )

    def test_wrong_schema_version(self) -> None:
        with self.assertRaises(ValueError):
            _common.validate_schema(
                {"schema_version": 99, "platform": "macos", "version": "1", "clusters": []},
                "analyze",
            )

    def test_missing_required(self) -> None:
        with self.assertRaises(ValueError):
            _common.validate_schema(
                {"schema_version": 1, "platform": "macos", "version": "1"},
                "analyze",
            )

    def test_unknown_file_kind(self) -> None:
        with self.assertRaises(ValueError):
            _common.validate_schema({"schema_version": 1}, "bogus")


if __name__ == "__main__":
    unittest.main()
