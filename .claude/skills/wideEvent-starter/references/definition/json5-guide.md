# JSON5 Wide Event Definition Guide (pixels/)

This guide covers the **legacy JSON5 flat-parameter format** stored under `pixels/definitions/`.

For complete example, see `examples/json5-auth-v2-token-refresh.json5`.

---

## Directory & File Naming

```
<platform>/PixelDefinitions/pixels/
├── params_dictionary.json5    # Shared parameter definitions (referenced by string)
├── suffixes_dictionary.json5  # Suffix definitions
└── definitions/               # Your definition files go here
    └── <feature_name>_wide_event.json5
```

- **iOS**: `iOS/PixelDefinitions/pixels/definitions/`
- **macOS**: `macOS/PixelDefinitions/pixels/definitions/`

**File name:** `<feature_name>_wide_event.json5` (e.g., `auth_v2_token_refresh_wide_event.json5`)

**Definition key (pixel name):**
- iOS: `m_ios_wide_<feature_name>`
- macOS: `m_mac_wide_<feature_name>`

Use the name from the Asana task if one is explicitly provided.

---

## params_dictionary.json5

Shared parameter definitions. Reference them by using the dictionary key as a **string** in the `parameters` array instead of a full object.

Example — if `params_dictionary.json5` defines `"appVersion"`, then in your definition:
```json5
"parameters": [
    "appVersion",   // ← string reference, expanded by the system
    { "key": "feature.data.ext.my_param", ... }  // ← inline custom param
]
```

Before writing, read the platform's dictionary:
- iOS: `iOS/PixelDefinitions/pixels/params_dictionary.json5`
- macOS: `macOS/PixelDefinitions/pixels/params_dictionary.json5`

Check:
- All referenced default param names exist in the dictionary
- Custom params don't duplicate dictionary entries (reference by key if they do)
- Type consistency (`string` vs `integer`)

---

## Output Template

Always use this skeleton when generating a definition. Fill in the `{{placeholders}}` — do not rearrange the structure.

```json5
// Defined in {{ASANA_TASK_URL}}
{
    "m_{{platform}}_wide_{{feature_name}}": {
        "description": "{{one-line description of when this event fires}}",
        "owners": [{{owners}}],
        "triggers": [{{triggers}}],
        "suffixes": [{{suffixes}}],
        "parameters": [
            // === Platform defaults (from wide event format + params_dictionary.json5) ===
            {{platform_default_params}}
            // === Custom parameters ===
            {
                "key": "meta.type",
                "type": "string",
                "description": "Wide event type identifier",
                "enum": ["{{platform_lowercase}}-{{feature-name-hyphens}}"]
            },
            {
                "key": "feature.name",
                "type": "string",
                "description": "Feature identifier for this wide event",
                "enum": ["{{feature-name-hyphens}}"]
            },
            // ... feature.data.ext.* params ...
        ]
    }
}
```

Where:
- `{{platform}}` — `ios` or `mac`
- `{{platform_lowercase}}` — `ios` or `macos` (used in `meta.type`)
- `{{feature-name-hyphens}}` — feature name with hyphens (e.g., `authv2-token-refresh`)
- `{{platform_default_params}}` — derived from the wide event format (fetched from Asana) + `params_dictionary.json5`. To determine which and in what order:
  1. Read the required/optional fields from the wide event format
  2. Cross-reference with `params_dictionary.json5` to find matching key names
  3. Check existing definitions in `examples/` for conventional ordering
  4. iOS includes `wideEventFormFactor`; macOS does not. Not all defaults are needed for every event — compare with existing definitions.

### Status values
Include only the statuses your event actually uses:
- **SUCCESS** — unit of work completed successfully
- **FAILURE** — include error parameters when this status is used
- **CANCELLED** — user deliberately exited the flow
- **UNKNOWN** — sent before knowing final state; typically includes `status_reason`

### Error parameters

Include as flat parameter objects when the event can have `FAILURE` status:

```json5
{
    "key": "feature.data.error.domain",
    "type": "string",
    "description": "The top level error domain"
},
{
    "key": "feature.data.error.code",
    "type": "integer",
    "description": "The top level error code"
},
{
    "key": "feature.data.error.underlying_domain",
    "type": "string",
    "description": "The underlying error domain"
},
{
    "key": "feature.data.error.underlying_code",
    "type": "integer",
    "description": "The underlying error code"
}
```

---

## Custom Parameters (feature.data.ext.*)

See `parameter-formats.md` for the full syntax reference with examples for each type (string enum, integer bucketed, boolean, free-form string, dynamic keyPattern).

General rules:
- For `string` params, always try to add an `enum` — ask the user if values aren't clear
- Use `keyPattern` (regex) for dynamic keys; escape dots: `feature\\.data\\.ext\\.`
- Use `examples` instead of `enum` when values are too numerous
- Bucket latency/duration values: `[1000, 5000, 10000, 30000, 60000, 300000, 600000]`
- Error descriptions must be static, developer-defined strings — never exception messages

---

## Platform Differences

| Aspect | iOS | macOS |
|--------|-----|-------|
| Pixel name prefix | `m_ios_wide_` | `m_mac_wide_` |
| `meta.type` enum prefix | `ios-` | `macos-` |
| `wideEventFormFactor` | Included | Omitted |
| Directory | `iOS/PixelDefinitions/pixels/definitions/` | `macOS/PixelDefinitions/pixels/definitions/` |

When creating for **both platforms**, create one file in each directory with the appropriate definition key prefix.

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
