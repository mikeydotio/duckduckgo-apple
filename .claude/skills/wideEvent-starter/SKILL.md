---
name: wideEvent-starter
description: End-to-end wide event creation for apple-browsers — from wide event definition (JSON5 or JSON format) to Swift data class and tests. Use this skill whenever the user wants to define a new wide event, create a wide event definition, create a wide event data class, add a wide event to PixelDefinitions, or provides an Asana link to a wide event task. Also trigger when the user mentions "wide event", "wide event definition", "wide event data class", or wants to add a definition to pixels/definitions/ or wide_events/definitions/ for a wide event, even if they don't explicitly say "definition".
---

# Wide Event Starter Skill

This skill is instructions and reference material — not an agent itself. Subagents don't have access to MCP servers (like Asana), so the main conversation must handle MCP calls first, then pass the results to a subagent.

**When this skill triggers, follow this sequence:**

1. **Main conversation: Gather context** — Do the MCP calls and user questions yourself (Steps 1–2 below). Subagents can't access MCP servers.
2. **Spawn subagent: Do the work** — Once you have the wide event format and the user's preferences, spawn a subagent briefed with:
   - The user's request (what wide event they need, platform, format preference)
   - The wide event format (the full text fetched from Asana or pasted by the user)
   - Any Asana task details (if the user provided a task link, fetch it and include the task description)
   - The skill path: `~/.claude/skills/wideEvent-starter/`
   - Instructions to read the relevant guide and follow Actions 1–2 below

The subagent writes definitions, creates Swift classes, runs tests, and reports back. If it needs more user input, it returns to the main conversation.

Wide event definitions (both JSON5 and JSON formats) are validated and used to generate a JSON Schema that the backend checks incoming events against. If the definition is wrong or incomplete, the backend will **drop the event** — so correctness matters.

Two actions, usable in sequence or independently:

| Action | What it does | Reference |
|--------|-------------|-----------|
| **Wide Event Definition** | Create the JSON5 or JSON definition file | `references/definition/` |
| **Data Class & Tests** | Create the Swift WideEventData class + XCTestCase | `references/data-class/` |

**Full flow:** Wide Event Definition → Data Class & Tests (+ SwiftLint) → Git Commit. At each transition, ask what the user wants next.

**Partial flow:** Figure out what exists and what the user is asking for, then run the relevant action.

---

## Before Spawning the Subagent (main conversation)

### Step 1 — Fetch the Wide Event Format

Run once per session, before writing the first definition. If the format has already been resolved in this conversation, reuse what's in context.

**Canonical format task ID:** `1211144309209145` ([Wide event format](https://app.asana.com/1/137249556945/project/1212203965891161/task/1211144309209145))

1. **Fetch from Asana:**
   - Use the Asana MCP `get_task` tool to fetch the canonical format task (ID above) with `opt_fields: "notes,name"`.
   - The task description (`notes` field) contains the full format. Read it carefully and in full.
   - Parse the field tables. For each field, extract: field name, data type, allowed values/enums, and description.
   - **Important:** The Asana task covers all platforms. Exclude parameters that only exist on non-Apple platforms (e.g., `app.dev_mode` is Android-only, `feature.data.ext.error.inner_exceptions` is Windows-only). Only include fields relevant to Apple (iOS/macOS).

2. **Use the format** as the working reference. Use **only** what it says — do not assume or invent fields, types, or values not in the format.

**If Asana MCP is unavailable:** Inform the user and ask them to paste the current wide event format directly. Wait for their response before writing any definition.

**If the format seems incomplete or ambiguous:** Ask the user rather than guessing.

### Step 2 — Choose Definition Format

Ask the user:

> Which format would you like?
> **(a)** JSON5 under `pixels/definitions/` (legacy flat-parameter format)
> **(b)** JSON under `wide_events/definitions/` (new nested-object format)

Skip if the user already indicated a preference (mentioned "wide_events" / "new format" / "JSON" → use JSON; mentioned "pixels" / provided existing JSON5 → use JSON5).

### Step 3 — Spawn Subagent and Create the Definition

Spawn a subagent with the wide event format text, user preferences, and any Asana task details. The subagent reads the corresponding guide:

- **(a) JSON5** → `references/definition/json5-guide.md`
- **(b) JSON** → `references/definition/json-guide.md`

Each guide has the format-specific schema, output template, platform differences, dictionary cross-referencing, and validation commands.

---

## Action 2: Data Class & Tests

See `references/data-class/guide.md` for the WideEventData protocol, class structure, and metadata setup. See `references/data-class/test-guide.md` for test class boilerplate, test categories, and how to run tests. See `examples/` for complete Swift files.

Prompt the user before creating. After creation, spawn a **subagent** to run tests and iteratively fix failures.

---

## Git Commit

1. Present summary of all created/modified files
2. Ask: "Would you like me to `git add` and commit?" → wait for approval
3. After commit, ask: "Ready to push?" → wait for approval

Never push without explicit go-ahead.
