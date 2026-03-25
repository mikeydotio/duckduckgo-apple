# macOS Release Workflow Documentation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single self-contained HTML file documenting macOS release workflows (Code Freeze, Internal Bump, Hotfix) with interactive flowcharts, collapsible detail panels, and inline troubleshooting.

**Architecture:** Single HTML file with inline CSS and JS. CSS handles layout (sticky sidebar, flowcharts via flexbox/grid, collapsible panels). JS handles scroll-spy for sidebar highlighting, expand/collapse toggling, and smooth-scroll cross-references. All workflow data is hardcoded in the HTML — no build step or data fetching.

**Tech Stack:** HTML5, CSS3 (flexbox/grid, transitions), vanilla JS (no frameworks), inline SVG for flowchart connectors.

**Spec:** `docs/superpowers/specs/2026-03-25-macos-release-workflow-docs-design.md`

---

## File Structure

- **Create:** `docs/macos-release-workflows.html` — the single output file containing everything

All workflow content is derived from reading these source files (read-only, not modified):
- `.github/workflows/macos_*.yml`
- `.github/actions/*/action.yml`
- `macOS/fastlane/Fastfile`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/*.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/*.rb`

---

## Important Context for Implementation

This is a documentation project, not an application. There are no tests. Each task builds up a section of the HTML file. The implementer must read the actual workflow files and fastlane plugin source to extract accurate details — the spec describes the structure, but the content comes from the source files.

**Color coding reference** (use consistently):
- `#3b82f6` (blue) — build jobs
- `#22c55e` (green) — test jobs
- `#f97316` (orange) — Asana/notification jobs
- `#a855f7` (purple) — tag/publish jobs
- `#ef4444` (red) — failure/troubleshooting

**Flowchart rendering approach:** Use CSS flexbox for layout with SVG `<line>` or `<path>` elements for connectors. Each job box is a `<div>` with colored left border. Parallel jobs use `display: flex; gap` side-by-side. Arrows are SVG overlays positioned with `position: absolute` relative to flowchart container.

---

### Task 1: HTML Skeleton, CSS Foundation, and JS Infrastructure

**Files:**
- Create: `docs/macos-release-workflows.html`

This task builds the empty page shell with all styling and interactivity infrastructure. No content yet — just the framework that all subsequent tasks fill in.

- [ ] **Step 1: Create the HTML file with document structure**

Write the HTML skeleton with:
- `<!DOCTYPE html>` and meta tags (charset, viewport)
- `<style>` block (empty, filled in step 2)
- `<script>` block (empty, filled in step 3)
- Body structure: `<nav class="sidebar">` + `<main class="content">`
- Sidebar with placeholder nav links for all sections: Overview, Code Freeze, Internal Release Bump, Hotfix, Common Components, Quick Reference
- Main content area with empty `<section>` elements with matching IDs
- Header with title "macOS Release Workflows" and intro paragraph

- [ ] **Step 2: Add all CSS**

Write the complete `<style>` block covering:
- Reset and base typography (system font stack: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`)
- Layout: sidebar `position: fixed; width: 220px; left: 0; top: 0; height: 100vh; overflow-y: auto`, main `margin-left: 240px; max-width: 1100px; padding: 2rem`
- Sidebar styling: nav links, `.active` state highlighting, section grouping
- Responsive: `@media (max-width: 768px)` — sidebar hidden, hamburger toggle visible
- Color variables using CSS custom properties for the 5 job-type colors
- Card styles for overview section: horizontal flex layout, hover effect, cursor pointer
- Flowchart styles: `.flow-chart` container with `position: relative`, `.flow-step` boxes with colored left border, `.flow-parallel` for side-by-side jobs, `.flow-arrow` for SVG connectors
- Collapsible panel styles: `.panel-header` with chevron icon, `.panel-body` with `max-height: 0; overflow: hidden; transition: max-height 0.3s`, `.panel.open .panel-body` with `max-height: none`
- Table styles for inputs/outputs
- Troubleshooting block styles: `.troubleshoot` with `border-left: 4px solid #ef4444; background: #fef2f2; padding: 1rem; margin: 1rem 0`
- Code/badge styles: inline code with background, `.fastlane-badge` for fastlane lane names
- Quick reference styles
- Expand/collapse all button styles
- Scroll margin for section anchors: `section[id] { scroll-margin-top: 2rem }`

- [ ] **Step 3: Add all JavaScript**

Write the complete `<script>` block with:
- `togglePanel(el)`: toggles `.open` class on closest `.panel` ancestor, rotates chevron
- `toggleAllPanels(sectionId, expand)`: expands or collapses all panels within a section, updates button text
- `scrollToSection(id)`: smooth-scrolls to section by ID, closes mobile sidebar if open
- Scroll-spy: `IntersectionObserver` watching all `section[id]` elements, updates `.active` class on corresponding sidebar link
- Mobile hamburger toggle: toggles sidebar visibility class
- `DOMContentLoaded` listener to initialize scroll-spy

- [ ] **Step 4: Verify the skeleton loads in browser**

Open `docs/macos-release-workflows.html` in a browser. Verify:
- Page loads without console errors
- Sidebar is visible on left with placeholder links
- Clicking sidebar links scrolls to (empty) sections
- Collapsible panel CSS transitions work (test with a dummy panel in HTML)
- Responsive breakpoint hides sidebar

- [ ] **Step 5: Commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add HTML skeleton with CSS and JS infrastructure for release workflow docs"
```

---

### Task 2: Overview Section with Flow Cards

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in the Overview `<section>`)

**Read these files for reference** (to verify job names and flow shapes):
- `.github/workflows/macos_code_freeze.yml`
- `.github/workflows/macos_bump_internal_release.yml`
- `.github/workflows/macos_hotfix.yml`
- `.github/workflows/macos_build_hotfix_release.yml`

- [ ] **Step 1: Build the three overview cards**

Add to the Overview section a `.overview-cards` flex container with three `.flow-card` children. Each card contains:
- Flow name as `<h3>`
- Trigger badge (e.g., "Scheduled — Mon 00:00 UTC", "Push to release/*", "Manual dispatch")
- Simplified vertical flowchart showing 5-7 boxes with job names only, connected by CSS arrows
- Key facts: branch pattern, concurrency group
- `onclick="scrollToSection('section-id')"` on each card

**Card content:**

Code Freeze card steps: Check Freeze Enabled → Create Release Branch → Run Tests (parallel: Unit + UI) → Bump Build Number → Build Release (parallel: DMG + App Store) → Tag & Merge → Publish to Sparkle

Internal Bump card steps: Validate Conditions → Run Tests → Bump Build Number → Build Release (parallel: DMG + App Store) → Tag & Merge → Publish to Sparkle

Hotfix card steps: Create Hotfix Branch (Phase 1) → Assert Branch → Run Tests → Bump & Update Asana → Build Release (parallel: DMG + App Store) → Tag & Merge → Publish (Manual)

Use the color coding: green for test steps, blue for build steps, orange for Asana steps, purple for tag/publish steps.

- [ ] **Step 2: Verify cards render correctly**

Open in browser. Verify:
- Three cards side-by-side with readable flowcharts
- Color coding is correct per job type
- Clicking each card scrolls to its (still empty) detailed section
- Cards wrap gracefully on narrow viewports

- [ ] **Step 3: Commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add overview section with flow summary cards"
```

---

### Task 3: Code Freeze Detailed Flow Section

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in Code Freeze `<section>`)

**Read these files to extract accurate details:**
- `.github/workflows/macos_code_freeze.yml` — main orchestrator
- `.github/workflows/macos_build_notarized.yml` — DMG build details
- `.github/workflows/macos_build_appstore.yml` — App Store build details
- `.github/workflows/macos_tag_release.yml` — tagging details
- `.github/workflows/macos_publish_dmg_release.yml` — publish details
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/start_new_release_action.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/bump_build_number_action.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/tag_release_action.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/assets/` — Asana templates

- [ ] **Step 1: Add section header with trigger details**

Add the Code Freeze section header:
- Title: "Code Freeze"
- Description: "Weekly scheduled release — creates a release branch, runs tests, builds DMG and App Store packages, tags the release, and publishes to Sparkle."
- Trigger: `macos_code_freeze.yml` — scheduled `cron: '0 0 * * 1'` (Monday 00:00 UTC) or manual `workflow_dispatch`
- Gate: only runs if `MACOS_AUTOMATIC_CODE_FREEZE == '1'` (for scheduled) or always for manual
- Dispatch inputs table: `version` (optional string — calculated if not provided)
- Concurrency: `macos-release` (cancel-in-progress: false)
- "Expand All / Collapse All" toggle button

- [ ] **Step 2: Add full interactive flowchart**

Build the Code Freeze flowchart showing all jobs with dependency arrows:
```
check_automatic_freeze (gate)
        ↓
create_release_branch
        ↓
   ┌────┴────┐
run_tests  ui_tests
   └────┬────┘
        ↓
increment_build_number
        ↓
prepare_release ──→ [macos_release.yml]
   ┌────┴────┐
   DMG    App Store
   └────┬────┘
        ↓
tag_and_merge ──→ [macos_tag_release.yml]
        ↓
publish_release ──→ [macos_publish_dmg_release.yml]
        ↓
(report_failure) [dashed, conditional: if any job fails]
```

Jobs calling reusable workflows get a link icon that scrolls to Common Components. Parallel jobs (run_tests + ui_tests, DMG + App Store) shown side-by-side. report_failure shown with dashed border.

- [ ] **Step 3: Add job detail panels — branch creation and tests**

Add collapsible panels for:

**check_automatic_freeze:**
- Runner: ubuntu-latest
- Purpose: Gate — skips scheduled runs if `MACOS_AUTOMATIC_CODE_FREEZE != '1'`
- No fastlane actions

**create_release_branch:**
- Runner: macos-26-xlarge (10 min timeout)
- Fastlane: `start_new_release` with `platform:macos`, `version` (if provided), `github_handle`
- Outputs: `release_branch_name`, `asana_task_id`, `asana_task_url`
- Asana: creates release task from template (ID: 1206127427850447), assigns to release DRI, updates with tasks from git log

**run_tests:**
- Calls: `macos_pr_checks.yml` with branch from create_release_branch
- Purpose: unit tests and shell checks

**ui_tests:**
- Calls: `macos_ui_tests.yml` with branch from create_release_branch
- Purpose: UI automation tests across macOS versions

- [ ] **Step 4: Add job detail panels — build and bump**

**increment_build_number:**
- Runner: macos-26-xlarge (10 min timeout)
- Needs: create_release_branch, run_tests, ui_tests
- Checks out release branch
- Fastlane: `bump_build_number` with `platform:macos`
- What it does: fetches latest build number from TestFlight and Sparkle appcast, increments, updates `BuildNumber.xcconfig`, pushes to git

**prepare_release:**
- Calls: `macos_release.yml` (→ Common Components link)
- Needs: create_release_branch, increment_build_number
- Inputs: asana-task-url from create_release_branch
- Fans out to DMG build (macos_build_notarized.yml) and App Store build (macos_build_appstore.yml) in parallel

- [ ] **Step 5: Add job detail panels — tag, publish, failure**

**tag_and_merge:**
- Calls: `macos_tag_release.yml` (→ Common Components link)
- Needs: prepare_release, increment_build_number
- Inputs: asana-task-url, prerelease: true
- What it does: creates prerelease tag `<version>-<build>+macos`, GitHub release with auto-generated notes, merges to main

**publish_release:**
- Calls: `macos_publish_dmg_release.yml` (→ Common Components link)
- Needs: create_release_branch, tag_and_merge
- What it does: generates Sparkle appcast (internal channel), uploads to S3, creates Asana validation task

**report_failure:**
- Calls: `report_failed_release_workflow.yml` (→ Common Components link)
- Condition: `if: always()` and any prior job failed
- Inputs: platform: macos, workflow-name: "code freeze"

- [ ] **Step 6: Add troubleshooting blocks**

Add troubleshooting blocks after relevant panels:

**After create_release_branch:**
- Failure: `start_new_release` can fail if release branch already exists or version conflict
- Recovery: check if branch exists in GitHub, delete if stale, re-run workflow

**After prepare_release (signing sync):**
- Failure: code signing sync has retry logic but can still fail
- Auto: Asana comment logged via `asana_log_message`
- Recovery: check match repo access, verify SSH key, re-run workflow

**After tag_and_merge:**
- Failure: merge conflicts with main, tag already exists
- Auto: `asana_create_action_item` with template `internal-release-tag-failed` — creates subtask assigned to release DRI describing manual merge steps
- Recovery: resolve conflicts locally, push, re-run tag_release manually

**After publish_release:**
- Failure: appcast generation, S3 upload, or Asana update failures
- Auto: `asana_create_action_item` with template `run-publish-dmg-release` — tells DRI to manually trigger `macos_publish_dmg_release.yml`
- Recovery: verify S3 credentials, check appcast format, re-run publish workflow with tag input

- [ ] **Step 7: Verify section renders and interactivity works**

Open in browser. Verify:
- Flowchart renders with correct colors and arrows
- All panels expand/collapse individually and via "Expand All"
- Troubleshooting blocks are visually distinct
- Links to Common Components sections work (scroll targets exist, even if empty)

- [ ] **Step 8: Commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Code Freeze detailed flow section"
```

---

### Task 4: Internal Release Bump Detailed Flow Section

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in Internal Bump `<section>`)

**Read these files to extract accurate details:**
- `.github/workflows/macos_bump_internal_release.yml` — main orchestrator
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/validate_internal_release_bump_action.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/update_asana_for_release_action.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/freeze_release_branch_action.rb`

- [ ] **Step 1: Add section header with trigger details**

- Title: "Internal Release Bump"
- Description: "Triggered automatically when code is pushed to a release branch. Validates conditions, runs tests, bumps build number, builds release, tags, and publishes to Sparkle."
- Trigger: `macos_bump_internal_release.yml` — push to `release/macos/**` (when SharedPackages/ or macOS/ changed, excluding fastlane/)
- Also: manual `workflow_dispatch` with inputs: `asana-task-url` (optional), `base-branch` (optional, default: main), `skip-appstore` (boolean, default: false)
- Concurrency: `macos-release` (cancel-in-progress: false)

- [ ] **Step 2: Add full interactive flowchart**

```
validate_input_conditions
        ↓
    run_tests [conditional: skip-release != 'true']
        ↓
increment_build_number
        ↓
prepare_release ──→ [macos_release.yml]
   ┌────┴────┐
   DMG    App Store [conditional: skip-appstore]
   └────┬────┘
        ↓
tag_and_merge ──→ [macos_tag_release.yml]
        ↓
publish_release ──→ [macos_publish_dmg_release.yml]
        ↓
(report_failure) [dashed]
```

- [ ] **Step 3: Add job detail panels**

**validate_input_conditions:**
- Runner: macos-26 (10 min timeout)
- Fastlane: `validate_internal_release_bump` with platform: macos
- What it does: finds or verifies release task in Asana, checks branch is not frozen (no draft GitHub release), verifies code changes exist (ignores .github, scripts, fastlane), validates release notes aren't empty/placeholder
- Outputs: skip-release, asana-task-id, asana-task-url, release-branch, skip-appstore

**increment_build_number:**
- Runner: macos-26 (10 min timeout)
- Fastlane: `bump_build_number` + `update_asana_for_release` (release_type: internal, target_section: MACOS_APP_BOARD_VALIDATION_SECTION_ID)
- Asana: moves tasks to Validation section, tags with release tag

**Other jobs** (prepare_release, tag_and_merge, publish_release, report_failure): link to Common Components with note about specific inputs passed (internal-release-bump: true for tag_and_merge)

- [ ] **Step 4: Add troubleshooting blocks**

**After validate_input_conditions:**
- Frozen branch: `validate_internal_release_bump` errors if draft GitHub release exists. This means a public release was decided. Skip further internal bumps until public release is tagged.
- Empty release notes: bump is blocked. Someone must fill in release notes in the Asana release task.
- No code changes: `skip-release` output set to `true`, workflow exits gracefully — not an error.
- Active hotfix blocks normal bump: if a hotfix task is found in Asana, normal internal bump is blocked.

**After tag_and_merge:**
- Failure: `asana_create_action_item` with template `internal-release-tag-failed`
- If merge to main fails: action item created with `merge-failed` template describing manual merge steps

- [ ] **Step 5: Verify and commit**

Open in browser, verify section renders correctly.

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Internal Release Bump detailed flow section"
```

---

### Task 5: Hotfix Detailed Flow Section

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in Hotfix `<section>`)

**Read these files to extract accurate details:**
- `.github/workflows/macos_hotfix.yml` — phase 1 (branch creation)
- `.github/workflows/macos_build_hotfix_release.yml` — phase 2 (build & release)
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/ddg_apple_automation_helper.rb` — `prepare_hotfix_branch` method

- [ ] **Step 1: Add section header with trigger details**

- Title: "Hotfix Release"
- Description: "Two-phase manual process. Phase 1 creates a hotfix branch from the latest public release tag. Phase 2 builds, tags, and prepares the hotfix for release. Publishing to Sparkle is a separate manual step."
- Phase 1 trigger: `macos_hotfix.yml` — manual `workflow_dispatch` only, must be run from main branch
- Phase 2 trigger: `macos_build_hotfix_release.yml` — manual `workflow_dispatch` with inputs: `asana-task-url` (required), `base-branch` (optional, default: main), `current-internal-release-branch` (optional)
- Concurrency: `macos-release` (cancel-in-progress: false)

- [ ] **Step 2: Add two-phase flowchart**

Show two connected flowcharts (Phase 1 and Phase 2) with a visual break between them indicating "manual trigger required":

Phase 1 (macos_hotfix.yml):
```
Assert main branch
      ↓
Create hotfix branch (start_new_release with is_hotfix: true)
      ↓
Report to Asana (template: hotfix-branch-ready)
```

Phase 2 (macos_build_hotfix_release.yml):
```
assert_release_branch
        ↓
    run_tests
        ↓
  update_asana (bump_build_number + update_asana_for_release)
        ↓
prepare_release ──→ [macos_release.yml]
   ┌────┴────┐
   DMG    App Store
   └────┬────┘
        ↓
tag_and_merge ──→ [macos_tag_release.yml]
        ↓
(report_failure) [dashed]

        ↓ [dashed, manual trigger]
Publish (macos_publish_dmg_release.yml) — run separately
```

The publish step shown with dashed border and "Manual Trigger" label — per spec reviewer's recommendation.

- [ ] **Step 3: Add job detail panels**

**Phase 1 — create_release_branch:**
- Runner: macos-26-xlarge (10 min timeout)
- Asserts main branch
- Fastlane: `start_new_release` with `is_hotfix: true`, platform: macos
- What it does: finds latest public release tag, creates `hotfix/macos/<version>` branch with patch version bump, creates Asana hotfix task from template (ID: 1206724592377782)
- Note: sets up Ruby dependencies twice (before and after branch checkout) because plugin version may differ on hotfix branch
- Asana: creates action item with template `hotfix-branch-ready`

**Phase 2 — assert_release_branch:**
- Runner: macos-26 (10 min timeout)
- Asserts current branch matches `hotfix/*`
- Extracts Asana task ID from input URL

**Phase 2 — update_asana:**
- Runner: macos-26 (10 min timeout)
- Fastlane: `bump_build_number` + `update_asana_for_release` (release_type: internal, target: MACOS_APP_BOARD_VALIDATION_SECTION_ID)

**Phase 2 — prepare_release:**
- Calls: `macos_release.yml` with destination: appstore (hotfixes always go to App Store)
- Note: `skip-appstore` is never true for hotfixes

**Phase 2 — tag_and_merge:**
- Calls: `macos_tag_release.yml` with prerelease: true, base-branch: `current-internal-release-branch` or main
- Key detail: if `current-internal-release-branch` is provided, merges hotfix there instead of main (so current internal release picks up the fix)

- [ ] **Step 4: Add troubleshooting blocks**

**After Phase 1:**
- Failure: must be run from main branch, fails otherwise
- Recovery: switch to main, re-run

**After tag_and_merge (Phase 2):**
- Merge target complexity: if `current-internal-release-branch` is provided, hotfix merges there. If not, merges to main. If merge fails, `merge-failed` action item created in Asana.
- Recovery: resolve merge conflicts manually, push

**After the manual publish note:**
- How to publish: manually trigger `macos_publish_dmg_release.yml` with inputs: asana-task-url, tag (from Phase 2), release-type: `hotfix`
- This runs `appcastManager.swift --release-hotfix-to-public-channel`

- [ ] **Step 5: Verify and commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Hotfix detailed flow section"
```

---

### Task 6: Common Components — Reusable Workflows

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in Common Components `<section>`, reusable workflows part)

**Read these files to extract accurate details:**
- `.github/workflows/macos_release.yml`
- `.github/workflows/macos_build_notarized.yml`
- `.github/workflows/macos_build_appstore.yml`
- `.github/workflows/macos_tag_release.yml`
- `.github/workflows/macos_publish_dmg_release.yml`
- `.github/workflows/macos_create_variants.yml`
- `.github/workflows/report_failed_release_workflow.yml`

- [ ] **Step 1: Add macos_release.yml panel**

Dispatcher workflow. Document:
- Inputs: asana-task-url, skip-appstore, destination
- Jobs: dmg-release (calls macos_build_notarized.yml with release-type: release, create-dmg: true) and appstore-release (calls macos_build_appstore.yml, conditional on skip-appstore)
- Secrets passed through

- [ ] **Step 2: Add macos_build_notarized.yml panel**

Document:
- Inputs: release-type (review/release/alpha), create-dmg, asana-task-url, branch, commit-sha, build-number-override, skip-notify
- Jobs: export-notarized-app (runner: macos-26-xlarge), create-dmg (runner: macos-26), mattermost
- Key steps: SSH key registration, submodule checkout, signing sync (with retry), Xcode selection, archive.sh, Sentry rules, dSYM upload to S3, DMG creation via `create-dmg` tool
- Signing lanes: `sync_signing_dmg_release`, `sync_signing_dmg_review`, `sync_signing_dmg_alpha` (by release-type)
- Artifacts: notarized app (.tar.xz), DMG, dSYM
- Upload destinations: s3 (official) or s3testbuilds (test)

Add troubleshooting block for signing sync retry logic.

- [ ] **Step 3: Add macos_build_appstore.yml panel**

Document:
- Inputs: destination (testflight/testflight_review/testflight_alpha/appstore), asana-task-url, branch, commit-sha, build-number-override, skip-notify
- Jobs: build (macos-26-xlarge) and upload (macos-26)
- Concurrency: `macos-appstore-build-{destination}` and `macos-appstore-upload-{destination}` (cancel-in-progress: true)
- Fastlane lanes: `build_{destination}`, `upload_{destination}`
- Artifacts: dSYM.zip, .pkg

- [ ] **Step 4: Add macos_tag_release.yml panel**

Document:
- Inputs: asana-task-url, base-branch, branch, commit-sha, prerelease, ignore-unreleased-changes, internal-release-bump
- Key logic: asserts release/* or hotfix/* branch, validates commit SHA, for public releases unfreezes branch (deletes draft release)
- Fastlane: `tag_release` with all parameters
- Tag format: prerelease `<version>-<build>+macos`, public `<version>+macos`
- Outputs: tag, stop_workflow
- Asana: templates for success/failure (internal-release-complete, public-release-tagged, merge-failed, delete-branch-failed)

Add troubleshooting block for tag conflicts and merge failures.

- [ ] **Step 5: Add macos_publish_dmg_release.yml panel**

Document:
- Inputs (dispatch): asana-task-url, base-branch, tag, release-type (internal/public/hotfix), ignore-unreleased-changes
- Inputs (call): asana-task-url, branch
- Jobs: tag-public-release (conditional, calls macos_tag_release.yml with prerelease: false), stop-workflow-if-needed, publish-to-sparkle, create-variants
- Sparkle pipeline: checks out main, downloads tag artifact, verifies tag format, extracts release notes from Asana, sets up Sparkle tools, fetches DMG, runs appcastManager.swift with appropriate flag, backs up old appcast, uploads new appcast to S3
- Asana: creates validation task (validate-check-for-updates-internal or validate-check-for-updates-public), uploads appcast patch + release notes to task
- Release annotation pixel (public/hotfix only)
- Release notification task in Asana Deployments project (public/hotfix only)

Add troubleshooting block for appcast generation failures, S3 upload failures (templates: appcast-failed-internal, appcast-failed-public, appcast-failed-hotfix).

- [ ] **Step 6: Add remaining workflow panels**

**macos_create_variants.yml:**
- Fetches variant config from Asana, creates DMG variants with different ATB/Origin parameters
- Matrix strategy for parallel variant creation

**report_failed_release_workflow.yml:**
- Inputs: asana-task-id, branch, commit-sha, platform, workflow-name
- Fastlane: `asana_report_failed_workflow` — logs failure with context, adds collaborators

- [ ] **Step 7: Verify and commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Common Components — reusable workflows section"
```

---

### Task 7: Common Components — Fastlane Plugin, Freeze Mechanism, Sparkle Pipeline

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in remaining Common Components subsections)

**Read these files to extract accurate details:**
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/actions/*.rb` — all action files
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/ddg_apple_automation_helper.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/git_helper.rb`
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/asana_helper.rb`

- [ ] **Step 1: Add fastlane plugin actions — release lifecycle group**

Compact entries for each action:

- `start_new_release`: Creates release/hotfix branch, bumps version, updates embedded files, creates Asana task from template, finds release DRI. Key params: platform, version, is_hotfix, github_handle.
- `validate_internal_release_bump`: Checks branch not frozen, code changes exist, release notes valid. Returns skip_release flag.
- `bump_build_number`: Fetches latest from TestFlight + Sparkle appcast, increments, updates BuildNumber.xcconfig, pushes.
- `calculate_next_build_number`: Like bump but returns number without committing. Used by alpha builds.
- `tag_release`: Creates git tag + GitHub release, merges/deletes branch. Handles prerelease vs public logic.
- `freeze_release_branch`: Creates draft GitHub release as freeze indicator.

- [ ] **Step 2: Add fastlane plugin actions — Asana integration group**

- `asana_find_release_task`: Finds active release task for current version. Searches Apple Releases section, only considers tasks from last 5 days. Reports if hotfix blocks normal bump.
- `update_asana_for_release`: Internal: moves to Validation, tags. Public: moves to Done, completes (except incidents/objectives), creates announcement.
- `asana_create_action_item`: Creates subtask under Automation subtask using ERB template. Key templates: merge-failed, delete-branch-failed, internal-release-tag-failed, run-publish-dmg-release.
- `asana_log_message`: Posts to Automation subtask, adds user as collaborator.
- `asana_add_comment`: Posts comment to task (direct text or template).
- `asana_report_failed_workflow`: Logs failure with context, adds commit author and workflow actor as followers.
- `asana_extract_task_id`: Parses task ID from v0/v1 Asana URLs.
- `asana_get_release_automation_subtask_id`: Finds the Automation subtask (oldest) under a release task.
- `asana_extract_task_assignee`: Gets task assignee ID.
- `asana_get_user_id_for_github_handle`: Maps GitHub username to Asana user ID via YAML file.

- [ ] **Step 3: Add fastlane plugin actions — notifications group**

- `mattermost_send_message`: Maps GitHub handle to Mattermost user, processes ERB template, posts to webhook. Used for build success/failure DMs.

- [ ] **Step 4: Add Release Branch Freeze Mechanism explainer**

Dedicated subsection explaining:
1. **Why**: prevents further internal releases once a version is ready for public release
2. **How it works**: `freeze_release_branch` creates a draft GitHub release named `<version>+<platform>` as a signal
3. **Blocking**: `validate_internal_release_bump` checks for draft release → if found, sets `skip-release: true` and errors
4. **Unfreezing**: `tag_release` (public) deletes the draft release before creating the real one
5. **When triggered**: `macos_promote_testflight.yml` calls `freeze_release_branch` when `freeze-release: true` (default)
6. **Manual unfreeze**: delete the draft release in GitHub to allow internal bumps again

- [ ] **Step 5: Add Sparkle/Appcast Pipeline explainer**

Dedicated subsection explaining:
1. **Sparkle tools setup**: downloaded from `sparkle-project/Sparkle` GitHub releases at build time
2. **appcastManager.swift**: Swift script with three modes:
   - `--release-to-internal-channel`: internal releases (code freeze, internal bump)
   - `--release-to-public-channel`: public releases
   - `--release-hotfix-to-public-channel`: hotfix releases
3. **Flow**: fetch current appcast from S3 → backup old version → generate new appcast with DMG and release notes → upload to S3
4. **Release notes**: extracted from Asana release task using `fetch_release_notes` helper
5. **Validation**: after upload, Asana validation task created for manual check-for-updates verification
6. **Config**: appcast URLs stored in `Configuration/App/Sparkle.xcconfig` per build config

- [ ] **Step 6: Verify and commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Common Components — fastlane actions, freeze mechanism, Sparkle pipeline"
```

---

### Task 8: Quick Reference Section

**Files:**
- Modify: `docs/macos-release-workflows.html` (fill in Quick Reference `<section>`)

**Read these files for accurate values:**
- `.github/workflows/macos_code_freeze.yml` (concurrency groups)
- `.github/workflows/macos_build_appstore.yml` (concurrency groups)
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/ddg_apple_automation_helper.rb` (branch/tag formats)
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/helper/asana_helper.rb` (template constants)
- `../fastlane-plugin-ddg_apple_automation/lib/fastlane/plugin/ddg_apple_automation/assets/` (template files list)

- [ ] **Step 1: Add branch naming and tag format tables**

Branch naming:
| Pattern | Example | Used By |
|---------|---------|---------|
| `release/macos/<version>` | `release/macos/7.5.0` | Code Freeze, Internal Bump |
| `hotfix/macos/<version>` | `hotfix/macos/7.5.1` | Hotfix |

Tag format:
| Type | Format | Example |
|------|--------|---------|
| Prerelease (internal) | `<version>-<build>+macos` | `7.5.0-100+macos` |
| Public | `<version>+macos` | `7.5.0+macos` |

- [ ] **Step 2: Add concurrency groups table**

| Group | Cancel-in-progress | Used By |
|-------|-------------------|---------|
| `macos-release` | false | Code Freeze, Internal Bump, Hotfix, Tag Release |
| `macos-appstore-build-{destination}` | true | App Store build jobs |
| `macos-appstore-upload-{destination}` | true | App Store upload jobs |

- [ ] **Step 3: Add secrets and env vars table**

Group secrets by purpose:
- Apple API: APPLE_API_KEY_BASE64, APPLE_API_KEY_ID, APPLE_API_KEY_ISSUER
- Code signing: MATCH_PASSWORD, SSH_PRIVATE_KEY_FASTLANE_MATCH, SSH_PRIVATE_KEY_DUCKSANS_FONT
- AWS/S3: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (2 variants: default + RELEASE_S3)
- Asana: ASANA_ACCESS_TOKEN
- Notifications: MM_WEBHOOK_URL
- Git: GHA_ELEVATED_PERMISSIONS_TOKEN
- Sparkle: SPARKLE_PRIVATE_KEY

GitHub Variables: MACOS_AUTOMATIC_CODE_FREEZE, MACOS_ALPHA_BUILD_NUMBER

- [ ] **Step 4: Add Asana template names table**

Read template files from plugin assets directory to list all templates with their purpose and when triggered. Include templates like: hotfix-branch-ready, debug-symbols-uploaded, dmg-uploaded, notarized-build-complete, validate-check-for-updates-internal, workflow-failed, merge-failed, etc.

- [ ] **Step 5: Add config files reference**

| File | Key | Purpose |
|------|-----|---------|
| `Configuration/Version.xcconfig` | MARKETING_VERSION | App version (e.g., 7.5.0) |
| `Configuration/BuildNumber.xcconfig` | CURRENT_PROJECT_VERSION | Build number (e.g., 100) |
| `Configuration/App/Sparkle.xcconfig` | Various | Appcast URLs per build config |

- [ ] **Step 6: Verify and commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: add Quick Reference section"
```

---

### Task 9: Final Polish and Verification

**Files:**
- Modify: `docs/macos-release-workflows.html`

- [ ] **Step 1: Verify all cross-reference links work**

Click through every link in the document:
- Overview cards → detailed sections
- Reusable workflow links in flowcharts → Common Components panels
- Fastlane action badges → plugin action entries
- Sidebar nav → all sections

Fix any broken anchor links.

- [ ] **Step 2: Verify responsive layout**

Resize browser to test:
- Sidebar collapses at 768px breakpoint
- Overview cards stack vertically on narrow screens
- Flowcharts remain readable
- Tables scroll horizontally if needed

- [ ] **Step 3: Verify expand/collapse behavior**

- All panels start collapsed
- "Expand All" / "Collapse All" toggles work per section
- Individual panel toggles work
- Chevron icons rotate correctly

- [ ] **Step 4: Spot-check content accuracy**

Pick 3-5 specific details and verify against source files:
- A workflow input parameter
- A fastlane lane name
- An Asana template name
- A branch naming pattern
- A concurrency group setting

- [ ] **Step 5: Final commit**

```bash
git add docs/macos-release-workflows.html
git commit -m "docs: polish and verify macOS release workflow documentation"
```
