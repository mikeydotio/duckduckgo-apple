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

## Cursor Cloud specific instructions

Cloud Agent VMs run **Linux x86_64**, but this is a native **Apple (iOS + macOS)** codebase.

- **The iOS and macOS browser apps cannot be built, run, or unit-tested in the Cloud Agent VM.** They require macOS + Xcode (`.xcode-version` pins the version) and Apple frameworks (UIKit/AppKit/WebKit). Every `xcodebuild`/Swift build, unit test, and UI test in CI runs on `macos-*` runners only. `swiftlint` also needs the Swift toolchain (not installed here) — see `README.md` / `development-commands.mdc` for the macOS build/lint/test commands.
- **What DOES run on Linux:** the Node/JS + pixel tooling exposed as npm scripts in `package.json`, `iOS/package.json`, and `macOS/package.json`. The startup update script (`npm install`) installs all workspace deps. Useful commands (run from `iOS/` or `macOS/`): `npm run rebuild-autoconsent` (rollup JS bundle), `npm run validate-pixel-defs` / `validate-defs-without-formatting`, `npm run check-wide-events`, `npm run pixel-lint`. The root `scripts/*.mjs` wide-event checkers are also Node-based.
- Running `validate-pixel-defs` / `rebuild-autoconsent` regenerates artifacts: `PixelDefinitions/wide_events/generated_schemas/` (gitignored) and `DuckDuckGo/Autoconsent/autoconsent-bundle.js` (tracked; output is normally identical). Verify `git status` is clean before committing.
- `npm run rebuild-autoconsent` from the repo root fails (no root `rollup.config.js`); the config lives in the `iOS/` and `macOS/` workspaces, so run it from there.
