"""Tests for the AsanaClient HTTP-parameter contract.

The Sentry Crash Group ID custom field is text-typed with comma-separated
values like `APPLE-IOS-DJC0,APPLE-IOS-DJ8M,...`. The search query MUST use
`custom_fields.<gid>.contains=<short_id>` (substring match), NOT
`custom_fields.<gid>.value=<short_id>` (whole-value exact match) — otherwise
the lookup never finds a task whose field carries multiple sibling
short-IDs, and every run creates a duplicate task.

This file pins the contract with a unit test so a future refactor can't
accidentally regress it.
"""

from __future__ import annotations

import unittest
from typing import Any
from unittest.mock import MagicMock, patch

from .. import _asana
from .._asana import AsanaClient


class _FakeSession:
    """Stand-in for requests.Session; lets us construct AsanaClient without
    pulling in the `requests` package (not always installed system-wide)."""

    def __init__(self) -> None:
        self.headers: dict[str, str] = {}

    def request(self, *a: Any, **kw: Any) -> Any:  # pragma: no cover
        # Never called in these tests — _request is patched at the AsanaClient
        # level. Defensive raise so a regression surfaces loudly.
        raise AssertionError("FakeSession.request should not be invoked")


class CustomFieldQueryParamTests(unittest.TestCase):
    def _client(self) -> AsanaClient:
        # Bypass __init__'s token check + skip the real requests import by
        # injecting a fake session.
        with patch.dict("os.environ", {"ASANA_ACCESS_TOKEN": "test-pat"}):
            return AsanaClient(session=_FakeSession())  # type: ignore[arg-type]

    def test_search_uses_contains_not_value(self) -> None:
        client = self._client()
        captured: dict[str, Any] = {}

        def fake_request(method, path, *, params=None, json=None, **kw):
            captured["method"] = method
            captured["path"] = path
            captured["params"] = params or {}
            return {"data": []}

        with patch.object(client, "_request", side_effect=fake_request):
            client.search_tasks(
                projects_any="1214294661819890",
                sections_any="1214290879396596",
                custom_field_contains=("1214294661819893", "APPLE-IOS-DJ8M"),
                opt_fields="gid",
            )

        params = captured["params"]
        # The load-bearing assertion: the URL param key is `.contains`.
        self.assertIn(
            "custom_fields.1214294661819893.contains",
            params,
            "search_tasks must use .contains for text-field substring matching; "
            "using .value matches only the whole field value (comma-separated "
            "multi-ID values never match).",
        )
        self.assertEqual(
            params["custom_fields.1214294661819893.contains"], "APPLE-IOS-DJ8M"
        )
        self.assertNotIn(
            "custom_fields.1214294661819893.value",
            params,
            ".value would do whole-string equality — wrong for this field.",
        )

    def test_search_omits_custom_field_filter_when_absent(self) -> None:
        client = self._client()
        captured: dict[str, Any] = {}

        def fake_request(method, path, *, params=None, json=None, **kw):
            captured["params"] = params or {}
            return {"data": []}

        with patch.object(client, "_request", side_effect=fake_request):
            client.search_tasks(
                projects_any="X",
                opt_fields="gid",
            )
        # No stray custom-field key when the caller didn't pass one.
        for key in captured["params"]:
            self.assertFalse(
                key.startswith("custom_fields."),
                f"unexpected custom-field key in params: {key}",
            )


if __name__ == "__main__":
    unittest.main()
