---
name: ddg-github-pr
description: >
  Creates GitHub pull requests for any DuckDuckGo team using the correct
  platform-specific PR template. Use this skill whenever asked to open, draft,
  or create a PR in a DuckDuckGo GitHub repository.
---

# DuckDuckGo GitHub PR Creation

## Step 1 — Detect the platform team

Determine which platform team owns the target repo:

| Repo contains | Team |
|---------------|------|
| `apple-browsers` | Apple |
| `windows-browser` | Windows |
| `android` | Android |
| Any other DDG repo | Use Apple template as default, note uncertainty |

## Step 2 — Gather required fields

Before creating the PR, collect:

- **Task/Issue URL** — the Asana task URL (required). Ask the user if not provided.
- **Tech Design URL** — link to a Tech Design doc if a design was created; leave blank otherwise.
- **CC** — Mattermost handles of people to notify; leave blank if none.
- **Description** — what changed and why.
- **Testing steps** — how a reviewer can manually verify the change.
- **Impact and risks** — what could go wrong; list rollback steps or mitigations.
- **Quality considerations** — automated test coverage; new tests added; note if none needed and why.

## Step 3 — Format by platform

### Apple (`apple-browsers`)

```
Task/Issue URL: <url>
Tech Design URL: <url or blank>
CC: <handles or blank>

### Description
<what changed and why>

### Testing Steps
<numbered steps to manually verify>

### Impact and Risks

#### What could go wrong?
<list risks and mitigations>

### Quality Considerations
<test coverage added; if no tests, explain why>

---

###### Internal references: [DoD](https://app.asana.com/0/1207634633537039) | [Eng Expectations](https://app.asana.com/0/199064865822552) | [Tech Design Template](https://app.asana.com/0/184709971311943)
```

### Windows (`windows-browser`)

```
Task/Issue URL: <url>
Tech Design URL: <url or blank>
Copy for release note: <user-facing release note sentence, or blank>
CC: <handles or blank>

Description

---
<what changed and why>

Steps to test this PR

---
<numbered steps to manually verify>

[PR Checklist](https://app.asana.com/0/1201007608267168)

Automated tests

---
<list test method names and CI labels added; or "No new automated tests — <reason>">
```

### Android

```
Task/Issue URL: <url>

### Description
<what changed and why>

### Steps to test this PR
- [ ] <step>
- [ ] <step>

### UI changes
| Before | After |
|--------|-------|
| <screenshot or N/A> | <screenshot or N/A> |
```

## Step 4 — Run `gh pr create`

Use a HEREDOC to pass the body:

```bash
gh pr create \
  --title "<short imperative title under 70 chars>" \
  --body "$(cat <<'EOF'
<filled template from Step 3>
EOF
)"
```

- Target branch: `main` unless the user specifies otherwise.
- Add `--draft` if the PR is not ready for review.
- Return the PR URL to the user when done.

## Apple Definition of Done (checklist before marking ready for review)

- [ ] PR description is complete with testing steps and risk assessment
- [ ] Manually tested on a real device (or simulator if appropriate)
- [ ] Happy path, error cases, and boundary conditions covered by automated tests
- [ ] Pixel / analytics events have tests
- [ ] No `// swiftlint:disable` added without justification
- [ ] CI is passing (or failures are understood and unrelated)
- [ ] User-visible strings are localized

## Key Asana References

| Document | GID |
|----------|-----|
| Apple Definition of Done | 1207634633537039 |
| Software Engineering Expectations | 199064865822552 |
| Technical Design Template | 184709971311943 |
