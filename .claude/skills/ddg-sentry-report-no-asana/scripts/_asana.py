"""Minimal Asana REST client used by the three scripts.

Wraps the small slice of the Asana API the scripts touch:
- GET    /tasks/<gid>
- GET    /workspaces/<workspace>/tasks/search
- POST   /tasks
- PUT    /tasks/<gid>
- POST   /tasks/<gid>/addFollowers

Auth is via ASANA_ACCESS_TOKEN env var. Rate-limit responses (429) are
retried up to 5 times with the Retry-After header honored.

Intentionally not the full official `asana` package — keeping the
dependency surface to `requests` only.
"""

from __future__ import annotations

import logging
import os
import time
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # only for type hints; `requests` is imported lazily at runtime
    import requests

API_BASE = "https://app.asana.com/api/1.0"
WORKSPACE_GID = "137249556945"  # DuckDuckGo workspace; constant for this skill

logger = logging.getLogger(__name__)


class AsanaError(RuntimeError):
    """Raised on Asana API failures the caller cannot reasonably retry."""

    def __init__(self, message: str, *, status: int | None = None, body: Any = None):
        super().__init__(message)
        self.status = status
        self.body = body


class AsanaClient:
    """Thin wrapper around the Asana REST API."""

    def __init__(self, token: str | None = None, *, session: "requests.Session | None" = None):
        token = token or os.environ.get("ASANA_ACCESS_TOKEN")
        if not token:
            raise AsanaError(
                "ASANA_ACCESS_TOKEN environment variable is not set. "
                "Create a Personal Access Token at https://app.asana.com/0/my-apps "
                "and export it before running."
            )
        try:
            import requests as _requests
        except ImportError as e:  # pragma: no cover
            raise AsanaError(
                "The `requests` package is required at runtime. "
                "Install it with: pip install -r scripts/requirements.txt"
            ) from e
        self._token = token
        self._session = session or _requests.Session()
        self._session.headers.update(
            {
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            }
        )

    # ---- low-level request --------------------------------------------------

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json: dict[str, Any] | None = None,
        max_retries: int = 5,
    ) -> dict[str, Any]:
        url = f"{API_BASE}{path}"
        for attempt in range(max_retries):
            logger.debug("Asana %s %s params=%s json=%s", method, path, params, json)
            response = self._session.request(method, url, params=params, json=json, timeout=30)

            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", "5"))
                logger.warning(
                    "Asana 429 rate limit; sleeping %ds (attempt %d/%d)",
                    retry_after,
                    attempt + 1,
                    max_retries,
                )
                time.sleep(retry_after)
                continue

            if response.status_code >= 500 and attempt < max_retries - 1:
                backoff = 2**attempt
                logger.warning(
                    "Asana %d; backing off %ds (attempt %d/%d)",
                    response.status_code,
                    backoff,
                    attempt + 1,
                    max_retries,
                )
                time.sleep(backoff)
                continue

            try:
                body = response.json()
            except ValueError:
                body = response.text

            if response.status_code >= 400:
                raise AsanaError(
                    f"Asana {method} {path} → {response.status_code}: {body}",
                    status=response.status_code,
                    body=body,
                )
            return body

        raise AsanaError(f"Asana {method} {path} exhausted {max_retries} retries")

    # ---- typed wrappers ----------------------------------------------------

    def get_task(self, task_gid: str, *, opt_fields: str) -> dict[str, Any]:
        """GET /tasks/<gid> with required opt_fields (must include tags,tags.name)."""
        if "tags" not in opt_fields or "tags.name" not in opt_fields:
            raise AsanaError(
                "get_task opt_fields must include 'tags,tags.name' "
                "(data-protection hook requirement)"
            )
        body = self._request("GET", f"/tasks/{task_gid}", params={"opt_fields": opt_fields})
        # Asana wraps single-task GETs in {"data": {...}} — unwrap to match
        # create_task/update_task (the rest of the script package expects the
        # task fields at the top level: ``existing.get("gid")``, etc.).
        return body["data"]

    def search_tasks(
        self,
        *,
        projects_any: str,
        sections_any: str | None = None,
        text: str | None = None,
        custom_field_value: tuple[str, str] | None = None,
        completed: bool | None = None,
        is_subtask: bool | None = None,
        opt_fields: str,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        """GET /workspaces/<workspace>/tasks/search.

        custom_field_value is a (custom_field_gid, value) tuple translated to
        the `custom_fields.<gid>.value` query param.
        """
        params: dict[str, Any] = {
            "projects.any": projects_any,
            "opt_fields": opt_fields,
            "limit": limit,
        }
        if sections_any is not None:
            params["sections.any"] = sections_any
        if text is not None:
            params["text"] = text
        if completed is not None:
            params["completed"] = "true" if completed else "false"
        if is_subtask is not None:
            params["is_subtask"] = "true" if is_subtask else "false"
        if custom_field_value is not None:
            cf_gid, value = custom_field_value
            params[f"custom_fields.{cf_gid}.value"] = value

        body = self._request(
            "GET",
            f"/workspaces/{WORKSPACE_GID}/tasks/search",
            params=params,
        )
        return body.get("data", [])

    def create_task(
        self,
        *,
        name: str,
        html_notes: str,
        parent_gid: str | None = None,
        project_gid: str | None = None,
        section_gid: str | None = None,
        custom_fields: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """POST /tasks. Returns the created task dict (gid + permalink_url)."""
        data: dict[str, Any] = {
            "name": name,
            "html_notes": html_notes,
        }
        if parent_gid is not None:
            data["parent"] = parent_gid
        if project_gid is not None:
            data["projects"] = [project_gid]
        if section_gid is not None:
            data["memberships"] = [{"project": project_gid, "section": section_gid}]
        if custom_fields:
            data["custom_fields"] = custom_fields

        body = self._request(
            "POST",
            "/tasks",
            params={"opt_fields": "gid,permalink_url"},
            json={"data": data},
        )
        return body["data"]

    def update_task(
        self,
        task_gid: str,
        *,
        completed: bool | None = None,
        html_notes: str | None = None,
        custom_fields: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """PUT /tasks/<gid>. At least one of the optional fields must be set."""
        data: dict[str, Any] = {}
        if completed is not None:
            data["completed"] = completed
        if html_notes is not None:
            data["html_notes"] = html_notes
        if custom_fields:
            data["custom_fields"] = custom_fields
        if not data:
            raise AsanaError("update_task called with no fields to update")

        body = self._request(
            "PUT",
            f"/tasks/{task_gid}",
            params={"opt_fields": "gid,permalink_url"},
            json={"data": data},
        )
        return body["data"]

    def add_followers(self, task_gid: str, *, followers: list[str]) -> None:
        """POST /tasks/<gid>/addFollowers."""
        if not followers:
            return
        self._request(
            "POST",
            f"/tasks/{task_gid}/addFollowers",
            json={"data": {"followers": followers}},
        )
