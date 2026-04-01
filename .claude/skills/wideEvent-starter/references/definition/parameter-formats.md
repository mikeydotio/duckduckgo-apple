# Parameter Formats

Reference for custom parameter syntax in both definition formats. Both formats support the same parameter types but use different syntax.

---

## String with enum

**JSON5 (pixels/):**
```json5
{
    "key": "feature.data.ext.refresh_trigger",
    "type": "string",
    "description": "What caused the token refresh to begin",
    "enum": ["backend", "client", "token_adoption"]
}
```

**JSON (wide_events/):**
```json
"refresh_trigger": {
    "type": "string",
    "description": "What caused the token refresh to begin",
    "enum": ["backend", "client", "token_adoption"]
}
```

## Integer with bucketed enum

Standard latency/duration buckets: `[1000, 5000, 10000, 30000, 60000, 300000, 600000]`

**JSON5 (pixels/):**
```json5
{
    "key": "feature.data.ext.refresh_token_latency_ms_bucketed",
    "type": "integer",
    "description": "Bucketed latency for token refresh step (ms)",
    "enum": [1000, 5000, 10000, 30000, 60000, 300000, 600000]
}
```

**JSON (wide_events/):**
```json
"refresh_token_latency_ms_bucketed": {
    "type": "integer",
    "description": "Bucketed latency for token refresh step (ms)",
    "enum": [1000, 5000, 10000, 30000, 60000, 300000, 600000]
}
```

## Boolean

**JSON5 (pixels/):**
```json5
{
    "key": "feature.data.ext.free_trial_eligible",
    "type": "boolean",
    "description": "Whether a free trial was available"
}
```

**JSON (wide_events/):**
```json
"free_trial_eligible": {
    "type": "boolean",
    "description": "Whether a free trial was available"
}
```

## Free-form string (use sparingly — prefer enums)

**JSON5 (pixels/):**
```json5
{
    "key": "feature.data.ext.subscription_identifier",
    "type": "string",
    "description": "Subscription product identifier",
    "examples": ["ddg.privacy.pro.monthly.renews.us", "ddg.privacy.pro.yearly.renews.us"]
}
```

**JSON (wide_events/):**
```json
"subscription_identifier": {
    "type": "string",
    "description": "Subscription product identifier"
}
```

## Dynamic key with keyPattern (JSON5 only)

Used when the key name itself is variable. Escape dots in the regex pattern.

```json5
{
    "keyPattern": "feature\\.data\\.ext\\.(bookmarks|passwords)_status",
    "type": "string",
    "description": "Status of each type",
    "enum": ["SUCCESS", "FAILURE", "CANCELLED", "UNKNOWN"]
}
```

## Dictionary reference (JSON only)

Reference a reusable property from `props_dictionary.json` by using its key as a string value instead of an inline object.

```json
"application_state": "foregroundBackgroundState"
```

The schema generator expands the string into the full property definition from the dictionary.
