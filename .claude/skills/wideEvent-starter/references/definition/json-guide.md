# JSON Wide Event Definition Guide (wide_events/)

This guide covers the **new JSON nested-object format** stored under `wide_events/definitions/`.

For complete example, see `examples/json-auth-v2-token-refresh.json`.

---

## Directory & File Naming

```
<platform>/PixelDefinitions/wide_events/
├── base_event.json          # Common fields inherited by all wide events
├── props_dictionary.json    # Reusable property definitions (referenced by string)
└── definitions/             # Your definition files go here
    └── <feature-name>.json5
```

- **iOS**: `iOS/PixelDefinitions/wide_events/definitions/`
- **macOS**: `macOS/PixelDefinitions/wide_events/definitions/`

**File name:** `<feature-name>.json5` (e.g., `auth-v2.json5`)

**Definition key:** The `meta.type` value — `<platform_prefix>-<feature-name>` (e.g., `ios-authv2-token-refresh`).

macOS may not have `base_event.json` or `props_dictionary.json` yet. If missing, create them by adapting the iOS versions (see Platform Differences below).

---

## base_event.json

Defines the common fields every wide event inherits. You do **not** repeat these in your definition — they're merged automatically.

| Section | Fields | Notes |
|---------|--------|-------|
| `app` | `name`, `version`, `form_factor` | iOS includes `form_factor`; macOS omits it |
| `global` | `platform`, `type`, `sample_rate`, `is_first_daily_occurrence` | `platform` enum differs per platform |
| `feature` | `name`, `status` | You override these in your definition |
| `context` | `name` | Optional context identifier |
| `meta` | `version` | Base version (single integer); combined with your two-octet version |

---

## props_dictionary.json

Reusable property definitions. Reference them by using the dictionary key as a **string value** in your definition instead of an inline object.

Example — if `props_dictionary.json` contains:
```json
{
    "foregroundBackgroundState": {
        "type": "string",
        "description": "Whether the app is in the foreground or background",
        "enum": ["foreground", "background"]
    }
}
```

Then in your definition:
```json
"application_state": "foregroundBackgroundState"
```

The schema generator expands the string into the full property definition.

Before writing, read the platform's dictionary:
- iOS: `iOS/PixelDefinitions/wide_events/props_dictionary.json`
- macOS: `macOS/PixelDefinitions/wide_events/props_dictionary.json` (create if missing)

Check:
- Reusable props referenced by string value exist in the dictionary
- Custom params don't duplicate dictionary entries
- Type consistency

---

## Output Template

Always use this skeleton when generating a definition. Fill in the `{{placeholders}}`.

```json
{
    "{{platform_prefix}}-{{feature-name}}": {
        "description": "{{one-line description}}",
        "owners": ["{{github-username}}"],
        "meta": {
            "type": "{{platform_prefix}}-{{feature-name}}",
            "version": "{{major}}.{{minor}}"
        },
        "feature": {
            "name": "{{feature-name}}",
            "status": [{{status_values}}],
            "data": {
                "ext": {
                    // Custom parameters as nested objects or dictionary refs
                },
                "error": {
                    // Include if feature can fail — see Error Fields below
                }
            }
        }
    }
}
```

Where:
- `{{platform_prefix}}` — `ios` or `macos`
- `{{feature-name}}` — hyphenated (e.g., `authv2-token-refresh`)
- `{{major}}.{{minor}}` — two-octet version (e.g., `0.1`); combined with base_event version automatically
- `{{status_values}}` — subset of `"SUCCESS", "FAILURE", "CANCELLED", "UNKNOWN"` that this event uses

### Status values
Include only the statuses your event actually uses:
- **SUCCESS** — unit of work completed successfully
- **FAILURE** — include error fields when this status is used
- **CANCELLED** — user deliberately exited the flow
- **UNKNOWN** — sent before knowing final state; typically includes `status_reason`

### Error fields

Include under `feature.data.error` when the event can have `FAILURE` status:

```json
"error": {
    "domain": {
        "type": "string",
        "description": "The top level error domain"
    },
    "code": {
        "type": "integer",
        "description": "The top level error code"
    },
    "underlying_domain": {
        "type": "string",
        "description": "The underlying error domain"
    },
    "underlying_code": {
        "type": "integer",
        "description": "The underlying error code"
    }
}
```

---

## Custom Parameters (feature.data.ext)

Parameters go inside `feature.data.ext` as nested objects. See `parameter-formats.md` for the full syntax reference with examples for each type (string enum, integer bucketed, boolean, free-form string, dictionary reference).

General rules:
- For `string` params, always try to add an `enum` — ask the user if values aren't clear
- Use `examples` instead of `enum` when values are too numerous
- Bucket latency/duration values: `[1000, 5000, 10000, 30000, 60000, 300000, 600000]`
- Error descriptions must be static, developer-defined strings — never exception messages

---

## Platform Differences

| Aspect | iOS | macOS |
|--------|-----|-------|
| Definition key prefix | `ios-` | `macos-` |
| `base_event.json` `global.platform` enum | `["iOS"]` | `["macOS"]` |
| `base_event.json` `app.form_factor` | Included (`phone`, `tablet`) | Omitted |
| `base_event.json` `app.name` enum | `["DuckDuckGo", "DuckDuckGo-Alpha", "DuckDuckGo-Experimental"]` | Platform-specific app names |
| Directory | `iOS/PixelDefinitions/wide_events/` | `macOS/PixelDefinitions/wide_events/` |

When creating for **both platforms**, create one definition file per platform with the appropriate key prefix.

---

## Validation & Lint

The validation script validates definitions and auto-generates schemas. Run it for the platform you're targeting:

```bash
# From the platform directory (iOS/ or macOS/)
cd <repo_root>/<platform_dir>
npm install

# Validate definitions (both pixels/ and wide_events/) and generate schemas
npm run validate-pixel-defs

# Format/lint fix
npm run pixel-lint.fix
```

To validate wide event debug logs from the iOS Simulator (requires a booted simulator with the app installed):
```bash
cd <repo_root>/<platform_dir> && ./scripts/validate_wide_events.sh
```

This script runs `npm run validate-pixel-defs` first, then validates runtime logs at `Library/Caches/wide-event-validation-log.jsonl` against the generated schemas.

If validation fails: read the error, fix the definition, re-run until passing.
