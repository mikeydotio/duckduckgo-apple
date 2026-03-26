# Suggestions Processor — Rust Rewrite Design

## Overview

Rewrite the core suggestion scoring and processing logic from BrowserServicesKit's `Suggestions` Swift module in Rust. The Rust crate (`suggestions_processor`) handles scoring, ranking, deduplication, and top-hits selection. The Swift layer retains data fetching (`SuggestionLoading`) and all protocol/type definitions. A new Swift package (`SuggestionProcessing`) wraps the Rust binary via FFI, following the same pattern as `URLPredictor`/`URLPredictorRust`.

Cross-platform reuse (iOS, Android, Windows) is a key motivation.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Swift                                      │
│                                             │
│  SuggestionLoader  ──fetches data──►        │
│       │                                     │
│       ▼                                     │
│  SuggestionProcessing (new Swift package)   │
│       │  encodes input JSON                 │
│       │  calls ddg_sp_process_json()        │
│       │  decodes output JSON                │
│       ▼                                     │
│  SuggestionResult (existing type)           │
└────────────┬────────────────────────────────┘
             │ FFI (C ABI, JSON strings)
┌────────────▼────────────────────────────────┐
│  Rust (suggestions_processor)               │
│                                             │
│  Input JSON ──► deserialize                 │
│       │                                     │
│       ▼                                     │
│  ScoringService  (url crate for parsing)    │
│       │                                     │
│       ▼                                     │
│  ProcessingPipeline (12-step algorithm)     │
│       │                                     │
│       ▼                                     │
│  serialize ──► Output JSON                  │
└─────────────────────────────────────────────┘
```

## FFI Surface

Two exported C functions:

```rust
#[no_mangle]
pub extern "C" fn ddg_sp_process_json(input: *const c_char) -> *mut c_char

#[no_mangle]
pub extern "C" fn ddg_sp_free_string(ptr: *mut c_char)
```

Data crosses the boundary as JSON strings (single blob in, single blob out). This matches the URLPredictor pattern and keeps the FFI surface minimal.

### Input JSON Schema

```json
{
  "query": "duck",
  "platform": "desktop",
  "bookmarks": [
    { "url": "https://example.com", "title": "Example", "is_favorite": true }
  ],
  "history": [
    {
      "url": "https://example.com",
      "title": "Example",
      "number_of_visits": 5,
      "last_visit": 1711497600,
      "failed_to_load": false
    }
  ],
  "open_tabs": [
    { "url": "https://example.com", "title": "Example", "tab_id": "abc" }
  ],
  "internal_pages": [
    { "title": "Settings", "url": "duck://settings" }
  ],
  "api_result": [
    { "phrase": "duckduckgo" },
    { "phrase": "duck recipes", "is_nav": true }
  ]
}
```

- `platform`: `"desktop"` or `"mobile"`
- `history.last_visit`: Unix timestamp (seconds)
- `api_result`: optional, flattened array of phrase/nav items

### Output JSON Schema

```json
{
  "top_hits": [
    {
      "type": "bookmark",
      "title": "Example",
      "url": "https://example.com",
      "is_favorite": true,
      "score": 3072
    }
  ],
  "ddg_suggestions": [
    { "type": "phrase", "phrase": "duckduckgo" }
  ],
  "local_suggestions": [
    { "type": "history_entry", "title": "Example", "url": "https://example.com", "score": 2048 }
  ],
  "can_be_autocompleted": true
}
```

Suggestion types: `phrase`, `website`, `bookmark`, `history_entry`, `internal_page`, `open_tab`, `unknown`, `ask_ai_chat`. Each carries fields relevant to its type (e.g. `tab_id` for open tabs, `is_favorite` for bookmarks).

## Rust Crate Structure

Location: `/Users/ayoy/code/suggestions_processor` (monorepo root, sibling to `url_predictor`)

```
suggestions_processor/
├── Cargo.toml
├── cbindgen.toml
├── scripts/
│   └── build_apple.sh
└── src/
    ├── lib.rs          # FFI exports, top-level process()
    ├── types.rs        # Input/output serde structs
    ├── scoring.rs      # Score function and helpers
    ├── processing.rs   # 12-step pipeline
    └── url_utils.rs    # naked_string, is_root, dropping_www_prefix
```

### Dependencies

```toml
[package]
name = "suggestions_processor"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["rlib", "cdylib", "staticlib"]

[dependencies]
url = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### Key Rust Types

```rust
// Input
struct ProcessInput {
    query: String,
    platform: Platform,
    bookmarks: Vec<BookmarkInput>,
    history: Vec<HistoryInput>,
    open_tabs: Vec<OpenTabInput>,
    internal_pages: Vec<InternalPageInput>,
    api_result: Option<Vec<ApiSuggestion>>,
}

enum Platform { Desktop, Mobile }

// Internal (not serialized)
struct ScoredSuggestion {
    kind: SuggestionKind,
    url: Url,
    title: String,
    visit_count: u32,
    failed_to_load: bool,
    score: i64,
    tab_id: Option<String>,
}

// Output
struct ProcessOutput {
    top_hits: Vec<SuggestionOutput>,
    ddg_suggestions: Vec<SuggestionOutput>,
    local_suggestions: Vec<SuggestionOutput>,
    can_be_autocompleted: bool,
}
```

### Scoring Algorithm

Direct port of `ScoringService.score()`:

| Condition | Points |
|-----------|--------|
| URL naked string starts with query | 300 |
| Title leading boundary starts with query | 200 |
| Domain contains query (query len > 2) | 150 |
| Title contains ` {query}` (query len > 2) | 100 |
| All query tokens match in title/URL boundaries | 10 (+ 70 if first token in URL start, + 50 if first token in title start) |
| Root domain bonus | +2000 |
| Visit count bonus (when score > 0) | score <<= 10, then += visit_count |

Quality ranking for deduplication: phrase(1) < website/internal_page(2) < history(3) < browser_tab(4) < bookmark(5) < favorite(6).

URL helpers (`naked_string`, `is_root`, `dropping_www_prefix`) implemented using the `url` crate.

### Processing Pipeline

12-step algorithm, direct port of `SuggestionProcessing.result(for:...)`:

1. Normalize query (lowercase, tokenize by whitespace)
2. Extract DDG API suggestions (phrase + website types)
3. Filter DDG domain/navigational suggestions
4. Score all local items (bookmarks, tabs, history, internal pages)
5. Deduplicate by normalized URL (pick best quality, sum visit counts, preserve all kinds)
6. Merge local navigational + DDG website suggestions, sort by score descending
7. Select top hits (max 2; website/favorite/history; mobile also allows bookmarks; history needs >3 visits or root domain)
8. Handle open tab special case (split if top suggestion is tab + other type)
9. Convert top hits to output format
10. Calculate remaining budget: min(12 - topHits - 5, queryLen + 1 - topHits)
11. Build local suggestions (history/bookmark/tab/internal, excluding top hits, limited by budget)
12. Assemble final result; limit DDG suggestions to 5 on mobile

Constants: `MAX_SUGGESTIONS = 12`, `MAX_TOP_HITS = 2`, `MIN_SUGGESTION_GROUP = 5`, `MAX_DDG_MOBILE = 5`.

## Swift Package (SuggestionProcessing)

Location: `SharedPackages/SuggestionProcessing/`

```
SharedPackages/SuggestionProcessing/
├── Package.swift
├── artifacts/
│   └── SuggestionsProcessorRust.xcframework    (local, built by script)
├── Sources/
│   └── SuggestionProcessing/
│       └── Processor.swift
└── Tests/
    └── SuggestionProcessingTests/
```

### Package.swift

```swift
let package = Package(
    name: "SuggestionProcessing",
    platforms: [.iOS(.v15), .macOS(.v11)],
    products: [
        .library(name: "SuggestionProcessing", targets: ["SuggestionProcessing"]),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
    ],
    targets: [
        .target(name: "SuggestionProcessing",
                dependencies: ["SuggestionsProcessorRust",
                               .product(name: "Suggestions", package: "BrowserServicesKit")]),
        .binaryTarget(name: "SuggestionsProcessorRust",
                      path: "artifacts/SuggestionsProcessorRust.xcframework"),
        .testTarget(name: "SuggestionProcessingTests",
                    dependencies: ["SuggestionProcessing"]),
    ]
)
```

Local xcframework path for development. Will switch to URL-based distribution when stable.

### Processor.swift — Public API

```swift
public enum Processor {
    public static func process(
        query: String,
        platform: Platform,
        bookmarks: [Bookmark],
        history: [HistorySuggestion],
        openTabs: [BrowserTab],
        internalPages: [InternalPage],
        apiResult: APIResult?
    ) throws -> SuggestionResult
}
```

Internally: encode inputs to JSON (`snake_case` key strategy), call `ddg_sp_process_json`, decode output, map JSON suggestion objects back to the existing `Suggestion` enum. Memory managed with `defer { ddg_sp_free_string(raw) }`.

## Migration

### Files removed from BrowserServicesKit/Sources/Suggestions

- `ScoringService.swift`
- `SuggestionProcessing.swift`

### Files unchanged

- `SuggestionLoading.swift`, `Suggestion.swift`, `SuggestionResult.swift`
- `APIResult.swift`, `Bookmark.swift`, `HistorySuggestion.swift`, `BrowserTab.swift`, `InternalPage.swift`

### Integration changes

- `SuggestionLoader` calls `Processor.process(...)` instead of `SuggestionProcessing().result(for:...)`
- BrowserServicesKit `Package.swift` adds dependency on `SuggestionProcessing`
- App-level `Package.swift` adds the `SuggestionProcessing` package

## Testing

### Rust tests

- `scoring.rs` — port assertions from `ScoreTests.swift`
- `processing.rs` — port assertions from `SuggestionProcessingTests.swift`
- `url_utils.rs` — tests for `naked_string`, `is_root`, `dropping_www_prefix`
- `lib.rs` — end-to-end JSON round-trip tests

### Swift tests

- `SuggestionProcessingTests` — round-trip tests verifying the wrapper encodes/decodes correctly
- Existing `SuggestionLoadingTests` must continue to pass after integration

## Build & Distribution

### Development (current phase)

1. Run `scripts/build_apple.sh` in `suggestions_processor/` to build xcframework
2. Output placed in `SharedPackages/SuggestionProcessing/artifacts/`
3. `Package.swift` references local path

### Production (later)

1. Build xcframework via CI
2. Upload to GitHub releases
3. Switch `Package.swift` to URL + checksum (one-line change)
