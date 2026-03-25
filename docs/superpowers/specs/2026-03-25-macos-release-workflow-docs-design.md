# macOS Release Workflow Documentation — Design Spec

## Goal

Create a single-file, self-contained HTML/JS interactive reference documenting the macOS release automation workflows for existing team members. Covers three release flows (Code Freeze, Internal Release Bump, Hotfix), their CI/CD mechanics, Asana integration, and troubleshooting/manual recovery paths.

## Audience

Existing team members who understand the basics of the release process but need a detailed reference for workflow parameters, job dependencies, Asana task management, and failure recovery.

## Scope

- **In scope**: Code Freeze, Internal Release Bump, Hotfix flows; reusable workflows; fastlane plugin actions; Asana integration (task templates, section moves, DRI assignment, failure reporting); Sparkle/appcast pipeline; troubleshooting and manual recovery
- **Out of scope**: Alpha release flow (handled separately later); iOS workflows

## Format

Single self-contained HTML file. No external dependencies — all CSS and JS inline. Can be opened directly from the filesystem or hosted on any static server.

---

## Page Structure

### 1. Header

- Title: "macOS Release Workflows"
- Brief intro paragraph: what this doc covers, who it's for, the three flows documented
- Last-updated date

### 2. Sticky Sidebar Navigation

- Fixed left sidebar showing all major sections
- Highlights current section based on scroll position
- Collapses to hamburger on narrow viewports (responsive)

### 3. Overview Section

Three cards arranged horizontally, one per release flow:

**Each card contains:**
- Flow name and trigger type (scheduled / push-triggered / manual)
- Simplified pipeline as 5-7 labeled boxes connected by vertical arrows, showing job names only
  - Code Freeze: Create Branch → Tests → Bump Build → Build (DMG + App Store) → Tag & Merge → Publish to Sparkle
  - Internal Bump: Validate → Tests → Bump Build → Build (DMG + App Store) → Tag & Merge → Publish to Sparkle
  - Hotfix: Assert Branch → Tests → Update Asana → Build (DMG + App Store) → Tag & Merge
- Key facts underneath: trigger mechanism, branch pattern, concurrency group
- Clicking a card smooth-scrolls to its detailed section

**Flowchart rendering:** Pure CSS flexbox with SVG connector lines. No external charting library.

**Color coding** (consistent throughout the entire page):
- Blue: build jobs
- Green: test jobs
- Orange: Asana/notification jobs
- Purple: tag/publish jobs
- Red: failure/troubleshooting

### 4. Detailed Flow Sections (one per flow)

Each flow section has identical internal structure:

#### 4a. Section Header
- Flow name, one-sentence description
- Trigger details: workflow file name, trigger type (schedule/push/dispatch), dispatch inputs with types and defaults
- Concurrency group and cancel-in-progress behavior

#### 4b. Full Interactive Flowchart
- All jobs as color-coded boxes with dependency arrows
- Parallel jobs (e.g., DMG + App Store builds) shown side-by-side
- Jobs that call reusable workflows get a link icon — clicking scrolls to Common Components section
- Conditional jobs shown with dashed borders and condition text

#### 4c. Job Detail Panels
One collapsible panel per job, ordered top-to-bottom matching the flowchart. Each panel contains:

- **Workflow file**: filename displayed as code, linking to Common Components if reusable
- **Runner**: machine type (e.g., `macos-26-xlarge`)
- **Timeout**: if specified
- **Inputs/Outputs**: table with parameter name, type, description, default value
- **Steps summary**: ordered list of what the job does; fastlane lanes displayed as inline code badges
- **Asana actions**: which templates are used, what tasks/comments get created, section moves
- **Artifacts**: what gets uploaded and where (S3 path, GitHub artifact name)

All panels collapsed by default. "Expand all" / "Collapse all" toggle at section level.

#### 4d. Inline Troubleshooting Blocks
Visually distinct (red-tinted left border, warning icon). Placed immediately after the job panel they relate to.

Each troubleshooting block contains:
- **What can go wrong**: common failure scenarios for that job
- **What happens automatically**: Asana action items created by `asana_create_action_item` — template name, who gets assigned, what the task description says
- **Manual recovery steps**: how to re-run the workflow or specific job, what inputs to provide, what state to verify before retrying

#### Flows documented:

**Code Freeze** (`macos_code_freeze.yml`):
- Jobs: check_automatic_freeze, create_release_branch, run_tests, ui_tests, increment_build_number, prepare_release (→ macos_release.yml), tag_and_merge (→ macos_tag_release.yml), publish_release (→ macos_publish_dmg_release.yml), report_failure
- Troubleshooting: signing sync failures (retry logic), test failures blocking release, tag conflicts, appcast generation failures, Asana update failures

**Internal Release Bump** (`macos_bump_internal_release.yml`):
- Jobs: validate_input_conditions, run_tests, increment_build_number, prepare_release, tag_and_merge, publish_release, report_failure
- Troubleshooting: frozen branch blocking bump, empty release notes, skip-release conditions, merge conflicts with main

**Hotfix** (`macos_hotfix.yml` + `macos_build_hotfix_release.yml`):
- Two-phase: branch creation (macos_hotfix.yml) then build/release (macos_build_hotfix_release.yml)
- Jobs (phase 2): assert_release_branch, run_tests, update_asana, prepare_release, tag_and_merge, report_failure
- Troubleshooting: hotfix branch assertion failures, merge to both main and current internal release branch, publish step is separate (manual via macos_publish_dmg_release.yml)

### 5. Common Components Section

#### 5a. Reusable Workflows
Collapsible panels with the same structure as job detail panels (inputs, outputs, steps, Asana actions). Each stands alone since called from multiple flows.

Workflows documented:
- `macos_release.yml` — dispatcher fanning out to DMG + App Store builds
- `macos_build_notarized.yml` — archive, notarize, optional DMG creation, dSYM upload
- `macos_build_appstore.yml` — build and upload to TestFlight/App Store with destination variants
- `macos_tag_release.yml` — tag creation, GitHub release with auto-generated notes, branch merge/deletion
- `macos_publish_dmg_release.yml` — Sparkle appcast generation, S3 upload, variant creation, Asana validation tasks
- `macos_create_variants.yml` — DMG variants with ATB/Origin parameters
- `report_failed_release_workflow.yml` — failure reporting to Asana

#### 5b. Fastlane Plugin Actions
Grouped by purpose, compact entries (what it does, key parameters, when it's called):

- **Release lifecycle**: `start_new_release`, `validate_internal_release_bump`, `bump_build_number`, `calculate_next_build_number`, `tag_release`, `freeze_release_branch`
- **Asana integration**: `asana_find_release_task`, `update_asana_for_release`, `asana_create_action_item`, `asana_log_message`, `asana_add_comment`, `asana_report_failed_workflow`, `asana_extract_task_id`, `asana_get_release_automation_subtask_id`, `asana_extract_task_assignee`, `asana_get_user_id_for_github_handle`
- **Notifications**: `mattermost_send_message`

#### 5c. Release Branch Freeze Mechanism
Dedicated explainer:
- How draft GitHub releases serve as freeze indicators
- `freeze_release_branch` creates the draft release
- `validate_internal_release_bump` checks for draft → blocks if frozen
- `tag_release` (public) unfreezes by deleting the draft
- When and why freezing happens (after `promote_testflight` with `freeze-release: true`)

#### 5d. Sparkle/Appcast Pipeline
- `appcastManager.swift` script and its three flags: `--release-to-internal-channel`, `--release-to-public-channel`, `--release-hotfix-to-public-channel`
- Appcast backup before overwrite
- S3 upload flow
- Sparkle tools setup (downloaded from GitHub releases)
- Release notes extraction from Asana task

### 6. Quick Reference (collapsible)

- **Branch naming**: `release/macos/<version>`, `hotfix/macos/<version>`
- **Tag format**: prerelease `<version>-<build>+macos`, public `<version>+macos`
- **Concurrency groups**: `macos-release` (no cancel), `macos-appstore-build-<dest>` / `macos-appstore-upload-<dest>` (cancel-in-progress)
- **Key secrets & env vars**: grouped table (Apple API, signing, AWS/S3, Asana, Mattermost)
- **Asana template names**: table mapping template name → purpose → when triggered
- **Config files**: `Configuration/Version.xcconfig` (MARKETING_VERSION), `Configuration/BuildNumber.xcconfig` (CURRENT_PROJECT_VERSION), `Configuration/App/Sparkle.xcconfig` (appcast URLs)

---

## Visual Design

- **Layout**: max-width 1100px centered content area, sticky left sidebar nav (~220px)
- **Typography**: system font stack, clean and readable
- **Theme**: light background, subtle section separators
- **Color coding**: blue (build), green (test), orange (Asana/notify), purple (tag/publish), red (troubleshooting)
- **Flowcharts**: CSS flexbox/grid layout with SVG connector lines between boxes
- **Collapsible panels**: all collapsed by default, expand/collapse all toggle per section, smooth expand animation
- **Cross-references**: clicking a reusable workflow name in a flow section scrolls to its Common Components entry; clicking a flow card in overview scrolls to detailed section
- **Responsive**: sidebar collapses on narrow viewports
- **No external dependencies**: all CSS and JS inline in the single HTML file

## Data Sources

All content is derived from:
- `.github/workflows/macos_*.yml` workflow files
- `.github/actions/` composite actions
- `macOS/fastlane/Fastfile` and related config files
- `../fastlane-plugin-ddg_apple_automation/` plugin source (actions and helpers)
- Asana template assets in the plugin's `assets/` directory

## Output

Single file: `docs/macos-release-workflows.html`
