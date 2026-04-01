---
name: wideEvent-starter
description: End-to-end wide event creation for apple-browsers — from wide event definition (JSON5 or JSON format) to Swift data class and tests. Use this skill whenever the user wants to define a new wide event, create a wide event definition, create a wide event data class, add a wide event to PixelDefinitions, or provides an Asana link to a wide event task. Also trigger when the user mentions "wide event", "wide event definition", "wide event data class", or wants to add a definition to pixels/definitions/ or wide_events/definitions/ for a wide event, even if they don't explicitly say "definition".
---

# Wide Event Starter Skill

This skill is instructions and reference material — not an agent itself. Subagents don't have access to MCP servers (like Asana), so the main conversation must handle MCP calls first, then pass the results to a subagent.

**When this skill triggers, follow this sequence:**

1. **Main conversation: Gather context** — Do the MCP calls and user questions yourself (Steps 1–3 below). Subagents can't access MCP servers.
2. **Spawn subagent: Do the work** — Once you have all the context, spawn a subagent briefed with:
   - The Asana task details (the proposed wide event description, parameters, owners, etc.)
   - The user's format preference (JSON5 or JSON)
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

### Step 1 — Get the Proposed Wide Event Task

Ask the user for the Asana task link for the proposed wide event, if they haven't already provided one:

> Could you share the Asana task link for this wide event?

Skip if the user already provided a link (e.g., `https://app.asana.com/1/137249556945/task/1212683300907458`).

### Step 2 — Fetch the Task from Asana

1. **Extract the task ID** from the URL (the numeric ID after `/task/`, stripping any query params like `?focus=true`).
2. **Fetch from Asana:** Use the Asana MCP `get_task` tool with `opt_fields: "notes"`.
3. **Read the task description** (`notes` field) carefully and in full. It contains the proposed wide event details: description, parameters, owners, expected statuses, etc.

**If Asana MCP is unavailable:** Ask the user to paste the task description directly.

**If the task description seems incomplete or ambiguous:** Ask the user for clarification rather than guessing.

### Step 3 — Choose Definition Format

Ask the user:

> Which format would you like?
> **(a)** JSON5 under `pixels/definitions/` (legacy flat-parameter format)
> **(b)** JSON under `wide_events/definitions/` (new nested-object format)

Skip if the user already indicated a preference (mentioned "wide_events" / "new format" / "JSON" → use JSON; mentioned "pixels" / provided existing JSON5 → use JSON5).

### Step 4 — Spawn Subagent and Create the Definition

Spawn a subagent with the Asana task details, user's format preference, and platform choice. The subagent reads the corresponding guide:

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
