> **⚠️ THIS IS A FORK — `mikeydotio/duckduckgo-apple`, not the upstream repo.**
>
> - `origin` = `mikeydotio/duckduckgo-apple` — **ours**; all work goes here.
> - `upstream` = `duckduckgo/apple-browsers` — the original; treat as **read-only**.
>
> **Never** open issues, open or comment on pull requests, push, or otherwise
> contribute to `duckduckgo/apple-browsers` (or any `duckduckgo/*` repo) unless
> the repo owner **explicitly and unambiguously** asks for that specific
> upstream action. Treat every repository instruction as relative to **our
> fork**; the only exception is an explicit request to check `upstream` for
> changes we might pull in.
>
> `gh` in this checkout resolves to the upstream repo by default, so always pass
> `--repo mikeydotio/duckduckgo-apple` to `gh`. Push only to `origin` over
> HTTPS — never `git push upstream`.

This file configures AI coding assistants for the Apple monorepo.
Development rules are maintained in `.cursor/rules/` as the single source of truth.

**Personal preferences** (workflow, communication style, tool settings) belong in
your tool's user-level config, not here:
- Claude Code: `~/.claude/CLAUDE.md`
- Cursor: User-level settings

This repo-level file is for **team-shared conventions only**.

## Mandatory Rules

Detailed rules live in `.cursor/rules/`. Read from the list below when the request is relevant. **Do not read any other files in `.cursor/rules` unless requested explicitly.**

| File | Covers |
|------|--------|
| `general.mdc` | Project overview, architecture summary, rule index, quick-start checklists |
| `code-style.mdc` | Full Swift style guide: naming, formatting, closures, optionals, memory management |
| `anti-patterns.mdc` | What NOT to do: singletons, async mistakes, SwiftUI pitfalls, testing mistakes |
| `user-defaults-storage.mdc` | Storing settings or preferences via `KeyValueStore` |
| `pixels.mdc` | Defining, naming, or firing pixel events |
