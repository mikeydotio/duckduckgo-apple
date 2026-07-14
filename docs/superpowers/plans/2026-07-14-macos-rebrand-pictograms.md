# macOS Rebrand Pictograms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give 7 macOS pictogram imagesets a rebrand-aware split so the app shows the new 2026 art when `isAppRebranded` is true and the current (pre-rebrand) art otherwise.

**Architecture:** For each in-scope imageset `X.imageset`, rename the existing (old-brand) imageset to `X-Legacy…` (Xcode auto-generates a `.xLegacy` symbol), create a fresh `X.imageset` holding the 2026 SVG (keeps the `.x` symbol), then update every call site to `isAppRebranded ? .x : .xLegacy`. This matches the pattern already in the codebase (e.g. `Sync-Start-128` / `Sync-Start-Legacy-128`, `PasswordManagementViewController.swift:1260`).

**Tech Stack:** Xcode asset catalogs (`.xcassets`, auto-generated image symbols via `GENERATE_ASSET_SYMBOLS`), Swift, SwiftUI/AppKit. `DesignSystemRebrand.isAppRebranded()` from `DesignResourcesKit`.

## Global Constraints

- **Source of new art:** `/Users/lantean/Developer/Icons-Main/Pictograms-2026/` (`56px/`, `96px/`, `128px-legacy/`). Copy SVGs verbatim; do not re-optimize.
- **Target catalog:** `macOS/DuckDuckGo/Assets.xcassets/` only. SubscriptionUI and SyncUI-macOS are out of scope for this plan.
- **Legacy imageset = the old art, unchanged.** The renamed folder keeps its existing SVG and `Contents.json` byte-for-byte.
- **New imageset = 2026 art**, reusing the legacy folder's `Contents.json` verbatim (the SVG filename inside is identical, so the reference stays valid).
- **`isAppRebranded` access:** call `DesignSystemRebrand.isAppRebranded()` (add `import DesignResourcesKit` where missing), except where a `themeManager` is already in scope — then use `themeManager.isAppRebranded`.
- **Do NOT touch:** `Response-DDG-96` / `.feedbackAsk` (already the legacy fallback in feedback views), the 8 already-migrated assets, and the 5 unused assets (`Clock-128`/HistoryViewOnboarding, `DataImport/Passwords-Add-96`, `BookmarksEmpty`, `Default-App-128`, `JoinedWaitlistHeader`).
- **No git commits.** Per the repo owner's standing preference, this plan intentionally contains no `git commit`/`git add` steps. Leave changes in the working tree for the owner to review and commit.
- **Verification is build + visual**, not unit tests — image selection has no unit-test surface. Each task builds the app; the final task visually smoke-checks each screen.

**Build command (used as the verification gate in every task):**
```bash
cd /Users/lantean/Developer/apple-browsers
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "macOS Browser" \
  -configuration Debug -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`. A missing/mistyped `.xLegacy` symbol fails compilation — that is the signal the asset rename landed correctly.

---

## File Structure

New/renamed asset folders (per task) under `macOS/DuckDuckGo/Assets.xcassets/`:

| In-scope imageset | Legacy folder (created by rename) | New symbol / legacy symbol | Source SVG(s) in Pictograms-2026 |
|---|---|---|---|
| `Images/Bookmarks-Import-128.imageset` | `Images/Bookmarks-Import-Legacy-128.imageset` | `.bookmarksImport128` / `.bookmarksImportLegacy128` | `128px-legacy/Bookmarks-Import-128.svg` |
| `Images/DuckDuckGo-Response-Heart.imageset` | `Images/DuckDuckGo-Response-Heart-Legacy.imageset` | `.duckDuckGoResponseHeart` / `.duckDuckGoResponseHeartLegacy` | `96px/DuckDuckGo-Response-Heart-96.svg` |
| `Images/newFireHeader.imageset` | `Images/newFireHeaderLegacy.imageset` | `.newFireHeader` / `.newFireHeaderLegacy` | `128px-legacy/Fire-128.svg` |
| `Images/HomePage/UpdatedBurnerWindowHome.imageset` | `Images/HomePage/UpdatedBurnerWindowHomeLegacy.imageset` | `.updatedBurnerWindowHome` / `.updatedBurnerWindowHomeLegacy` | `128px-legacy/Fire-Window-Light-128.svg` + `128px-legacy/Fire-Window-Dark-128.svg` |
| `Images/HistoryBurn.imageset` | `Images/HistoryBurnLegacy.imageset` | `.historyBurn` / `.historyBurnLegacy` | `96px/History-Burn-96.svg` |
| `Subscription-Clock-96.imageset` (catalog root) | `Subscription-Clock-Legacy-96.imageset` | `.subscriptionClock96` / `.subscriptionClockLegacy96` | `96px/Subscription-Clock-96.svg` |
| `Images/subscription-clock.imageset` | `Images/subscription-clock-Legacy.imageset` | `.subscriptionClock` / `.subscriptionClockLegacy` | `128px-legacy/Subscription-Clock-128.svg` |

Swift files modified (per task):
- `macOS/DuckDuckGo/Bookmarks/ViewModel/BookmarksEmptyStateContent.swift` + `macOS/DuckDuckGo/Bookmarks/View/BookmarksEmptyStateView.swift`
- `macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift`
- `macOS/DuckDuckGo/VisualRefresh/IconsProviding.swift`
- `macOS/DuckDuckGo/HomePage/View/BurnerHomePageView.swift`
- `macOS/DuckDuckGo/History/View/Dialogs/HistoryViewDeleteDialog.swift`
- `macOS/DuckDuckGo/WinBackOffer/WinBackOfferPromotionViewCoordinator.swift`
- `macOS/DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/WinBackOffer/WinBackOfferPromptView.swift`

**Shared shell helper** used by every asset task (defines the rename+create for a single-SVG imageset):
```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026

migrate_single() {   # $1 = imageset path relative to $ASSETS (no .imageset)   $2 = legacy path rel   $3 = svg filename   $4 = 2026 source rel to $SRC
  local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"
  test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }
  test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }
  mv "$orig" "$legacy"                 # old art becomes legacy (folder + Contents.json unchanged)
  mkdir -p "$orig"
  cp "$src" "$orig/$svg"               # 2026 art under the original name
  cp "$legacy/Contents.json" "$orig/Contents.json"   # reuse identical Contents.json (same svg filename)
  echo "OK: $1  (new=2026, legacy=old)"
}
```

---

### Task 1: Bookmarks-Import-128 (bookmark manager empty state)

**Files:**
- Rename: `macOS/DuckDuckGo/Assets.xcassets/Images/Bookmarks-Import-128.imageset` → `…/Bookmarks-Import-Legacy-128.imageset`
- Create: `macOS/DuckDuckGo/Assets.xcassets/Images/Bookmarks-Import-128.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/Bookmarks/ViewModel/BookmarksEmptyStateContent.swift:52-57`
- Modify: `macOS/DuckDuckGo/Bookmarks/View/BookmarksEmptyStateView.swift:65`

**Interfaces:**
- Produces symbols: `.bookmarksImport128` (new), `.bookmarksImportLegacy128` (old).
- `BookmarksEmptyStateContent.image` changes from a computed `var` to `func image(isAppRebranded: Bool) -> NSImage?`.

- [ ] **Step 1: Rename imageset and add 2026 art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Images/Bookmarks-Import-128" "Images/Bookmarks-Import-Legacy-128" "Bookmarks-Import-128.svg" "128px-legacy/Bookmarks-Import-128.svg"
```
Expected: `OK: Images/Bookmarks-Import-128`

- [ ] **Step 2: Verify both folders exist with the right art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
ls "$ASSETS/Images/Bookmarks-Import-128.imageset" "$ASSETS/Images/Bookmarks-Import-Legacy-128.imageset"
cmp "$ASSETS/Images/Bookmarks-Import-128.imageset/Bookmarks-Import-128.svg" "$SRC/128px-legacy/Bookmarks-Import-128.svg" && echo "NEW==2026"
```
Expected: both dirs list `Contents.json` + `Bookmarks-Import-128.svg`, and `NEW==2026`.

- [ ] **Step 3: Make the enum's image rebrand-aware**

In `BookmarksEmptyStateContent.swift`, replace the computed property (currently lines 52-57):

```swift
    var image: NSImage? {
        switch self {
        case .noBookmarks: .bookmarksImport128
        case .noSearchResults: .bookmarkEmptySearch
        }
    }
```

with:

```swift
    func image(isAppRebranded: Bool) -> NSImage? {
        switch self {
        case .noBookmarks: isAppRebranded ? .bookmarksImport128 : .bookmarksImportLegacy128
        case .noSearchResults: .bookmarkEmptySearch
        }
    }
```

- [ ] **Step 4: Update the render site**

In `BookmarksEmptyStateView.swift` line 65, replace:

```swift
            if let image = content.image {
```

with:

```swift
            if let image = content.image(isAppRebranded: DesignSystemRebrand.isAppRebranded()) {
```

(`BookmarksEmptyStateView.swift` already `import DesignResourcesKit` — no import change.)

- [ ] **Step 5: Build**

Run the Global-Constraints build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 2: DuckDuckGo-Response-Heart (quit survey header)

**Files:**
- Rename: `…/Images/DuckDuckGo-Response-Heart.imageset` → `…/Images/DuckDuckGo-Response-Heart-Legacy.imageset`
- Create: `…/Images/DuckDuckGo-Response-Heart.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/QuitSurvey/QuitSurveyView.swift:327`

**Interfaces:**
- Produces symbols: `.duckDuckGoResponseHeart` (new), `.duckDuckGoResponseHeartLegacy` (old).

- [ ] **Step 1: Rename imageset and add 2026 art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Images/DuckDuckGo-Response-Heart" "Images/DuckDuckGo-Response-Heart-Legacy" "DuckDuckGo-Response-Heart-96.svg" "96px/DuckDuckGo-Response-Heart-96.svg"
```
Expected: `OK: Images/DuckDuckGo-Response-Heart`

- [ ] **Step 2: Update the call site**

In `QuitSurveyView.swift` line 327, replace:

```swift
            Image(.duckDuckGoResponseHeart)
```

with:

```swift
            Image(DesignSystemRebrand.isAppRebranded() ? .duckDuckGoResponseHeart : .duckDuckGoResponseHeartLegacy)
```

(`QuitSurveyView.swift` already `import DesignResourcesKit` — no import change.)

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Fire-128 / newFireHeader (fire dialog header — provider-routed)

**Files:**
- Rename: `…/Images/newFireHeader.imageset` → `…/Images/newFireHeaderLegacy.imageset`
- Create: `…/Images/newFireHeader.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/VisualRefresh/IconsProviding.swift:57`

**Interfaces:**
- Produces symbols: `.newFireHeader` (new), `.newFireHeaderLegacy` (old).
- This asset flows through `IconsProviding.fireInfoGraphic`, whose `Legacy`/`Current` providers are already selected by the `.appRebranding` flag (`IconsProvidingFactory.buildColorsProvider`). The switch is therefore expressed via the provider split (equivalent to the inline ternary, but without bypassing the existing architecture). `CurrentIconsProvider.fireInfoGraphic` stays `.newFireHeader`; only `LegacyIconsProvider` changes.

- [ ] **Step 1: Rename imageset and add 2026 art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Images/newFireHeader" "Images/newFireHeaderLegacy" "Fire-128.svg" "128px-legacy/Fire-128.svg"
```
Expected: `OK: Images/newFireHeader`

- [ ] **Step 2: Point the legacy provider at the legacy art**

In `IconsProviding.swift`, in `final class LegacyIconsProvider` (line 57), replace:

```swift
    var fireInfoGraphic: NSImage = .newFireHeader
```

with:

```swift
    var fireInfoGraphic: NSImage = .newFireHeaderLegacy
```

Leave `CurrentIconsProvider.fireInfoGraphic` (line 70) as `.newFireHeader`.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 4: Fire-Window (Light+Dark) / UpdatedBurnerWindowHome (burner window home)

**Files:**
- Rename: `…/Images/HomePage/UpdatedBurnerWindowHome.imageset` → `…/Images/HomePage/UpdatedBurnerWindowHomeLegacy.imageset`
- Create: `…/Images/HomePage/UpdatedBurnerWindowHome.imageset` (2026 art, light + dark)
- Modify: `macOS/DuckDuckGo/HomePage/View/BurnerHomePageView.swift:53`

**Interfaces:**
- Produces symbols: `.updatedBurnerWindowHome` (new), `.updatedBurnerWindowHomeLegacy` (old).
- This imageset has TWO SVGs with a `luminosity`/`dark` appearance variant in `Contents.json`; both light and dark must be replaced. `migrate_single` handles only one SVG, so this task copies both explicitly.

- [ ] **Step 1: Rename imageset and add both 2026 SVGs**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
orig="$ASSETS/Images/HomePage/UpdatedBurnerWindowHome.imageset"
legacy="$ASSETS/Images/HomePage/UpdatedBurnerWindowHomeLegacy.imageset"
test -f "$SRC/128px-legacy/Fire-Window-Light-128.svg" && test -f "$SRC/128px-legacy/Fire-Window-Dark-128.svg" || { echo "MISSING SOURCE"; exit 1; }
mv "$orig" "$legacy"
mkdir -p "$orig"
cp "$SRC/128px-legacy/Fire-Window-Light-128.svg" "$orig/Fire-Window-Light-128.svg"
cp "$SRC/128px-legacy/Fire-Window-Dark-128.svg"  "$orig/Fire-Window-Dark-128.svg"
cp "$legacy/Contents.json" "$orig/Contents.json"
echo "done"; ls "$orig"
```
Expected: `Contents.json`, `Fire-Window-Dark-128.svg`, `Fire-Window-Light-128.svg` listed.

- [ ] **Step 2: Verify Contents.json still declares the dark appearance variant**

```bash
orig=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets/Images/HomePage/UpdatedBurnerWindowHome.imageset
grep -q '"luminosity"' "$orig/Contents.json" && grep -q 'Fire-Window-Dark-128.svg' "$orig/Contents.json" && echo "APPEARANCE OK"
```
Expected: `APPEARANCE OK`.

- [ ] **Step 3: Update the call site**

In `BurnerHomePageView.swift` line 53, replace:

```swift
                                Image(.updatedBurnerWindowHome)
```

with:

```swift
                                Image(themeManager.isAppRebranded ? .updatedBurnerWindowHome : .updatedBurnerWindowHomeLegacy)
```

(`BurnerHomePageView` already has `@EnvironmentObject var themeManager: ThemeManager` at line 35 — use it; no import change.)

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 5: History-Burn-96 / HistoryBurn (history delete dialog)

**Files:**
- Rename: `…/Images/HistoryBurn.imageset` → `…/Images/HistoryBurnLegacy.imageset`
- Create: `…/Images/HistoryBurn.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/History/View/Dialogs/HistoryViewDeleteDialog.swift` (add import + line 29)

**Interfaces:**
- Produces symbols: `.historyBurn` (new), `.historyBurnLegacy` (old).

- [ ] **Step 1: Rename imageset and add 2026 art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Images/HistoryBurn" "Images/HistoryBurnLegacy" "History-Burn-96.svg" "96px/History-Burn-96.svg"
```
Expected: `OK: Images/HistoryBurn`

- [ ] **Step 2: Add the DesignResourcesKit import**

In `HistoryViewDeleteDialog.swift`, after line 20 (`import SwiftUIExtensions`), add:

```swift
import DesignResourcesKit
```

- [ ] **Step 3: Update the call site**

In `HistoryViewDeleteDialog.swift` line 29, replace:

```swift
            Image(.historyBurn)
```

with:

```swift
            Image(DesignSystemRebrand.isAppRebranded() ? .historyBurn : .historyBurnLegacy)
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 6: Subscription-Clock-96 (win-back new-tab promotion)

**Files:**
- Rename: `…/Subscription-Clock-96.imageset` (catalog root) → `…/Subscription-Clock-Legacy-96.imageset`
- Create: `…/Subscription-Clock-96.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/WinBackOffer/WinBackOfferPromotionViewCoordinator.swift` (add import + line 114)

**Interfaces:**
- Produces symbols: `.subscriptionClock96` (new), `.subscriptionClockLegacy96` (old).
- `PromotionViewModel(image:)` takes an `NSImage`; pass the ternary result.

- [ ] **Step 1: Rename imageset and add 2026 art** (note: this imageset lives at the catalog root, not under `Images/`)

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Subscription-Clock-96" "Subscription-Clock-Legacy-96" "Subscription-Clock-96.svg" "96px/Subscription-Clock-96.svg"
```
Expected: `OK: Subscription-Clock-96`

- [ ] **Step 2: Add the DesignResourcesKit import**

In `WinBackOfferPromotionViewCoordinator.swift`, after line 24 (`import Subscription`), add:

```swift
import DesignResourcesKit
```

- [ ] **Step 3: Update the call site**

In `WinBackOfferPromotionViewCoordinator.swift` line 114, replace:

```swift
        return PromotionViewModel(image: .subscriptionClock96,
```

with:

```swift
        return PromotionViewModel(image: DesignSystemRebrand.isAppRebranded() ? .subscriptionClock96 : .subscriptionClockLegacy96,
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 7: subscription-clock (128) (win-back prompt) — replaces a string image reference

**Files:**
- Rename: `…/Images/subscription-clock.imageset` → `…/Images/subscription-clock-Legacy.imageset`
- Create: `…/Images/subscription-clock.imageset` (2026 art)
- Modify: `macOS/DuckDuckGo/NetworkProtection/AppTargets/BothAppTargets/WinBackOffer/WinBackOfferPromptView.swift` (add import + line 48)

**Interfaces:**
- Produces symbols: `.subscriptionClock` (new), `.subscriptionClockLegacy` (old).
- The current call site uses a STRING literal `Image("subscription-clock")`. After the rename that string would resolve to the new art unconditionally, so it must move to the symbol-based ternary.

- [ ] **Step 1: Rename imageset and add 2026 art**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
SRC=/Users/lantean/Developer/Icons-Main/Pictograms-2026
migrate_single() { local orig="$ASSETS/$1.imageset" legacy="$ASSETS/$2.imageset" svg="$3" src="$SRC/$4"; test -f "$src" || { echo "MISSING SOURCE: $src"; return 1; }; test -f "$orig/$svg" || { echo "MISSING ORIGINAL: $orig/$svg"; return 1; }; mv "$orig" "$legacy"; mkdir -p "$orig"; cp "$src" "$orig/$svg"; cp "$legacy/Contents.json" "$orig/Contents.json"; echo "OK: $1"; }
migrate_single "Images/subscription-clock" "Images/subscription-clock-Legacy" "Subscription-Clock-128.svg" "128px-legacy/Subscription-Clock-128.svg"
```
Expected: `OK: Images/subscription-clock`

- [ ] **Step 2: Confirm the SVG filename inside the imageset**

```bash
ASSETS=/Users/lantean/Developer/apple-browsers/macOS/DuckDuckGo/Assets.xcassets
ls "$ASSETS/Images/subscription-clock.imageset"
```
Expected: `Contents.json` and `Subscription-Clock-128.svg`. (If the original SVG had a different filename, `migrate_single` would have failed at Step 1 with `MISSING ORIGINAL` — in that case run `ls "$ASSETS/Images/subscription-clock-Legacy.imageset"`, note the real filename, and re-run passing that name as the 3rd arg.)

- [ ] **Step 3: Add the DesignResourcesKit import**

In `WinBackOfferPromptView.swift`, after line 21 (`import SwiftUIExtensions`), add:

```swift
import DesignResourcesKit
```

- [ ] **Step 4: Update the call site**

In `WinBackOfferPromptView.swift` line 48, replace:

```swift
            Image("subscription-clock")
```

with:

```swift
            Image(DesignSystemRebrand.isAppRebranded() ? .subscriptionClock : .subscriptionClockLegacy)
```

- [ ] **Step 5: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

---

### Task 8: Full verification & visual smoke test

**Files:** none (verification only).

- [ ] **Step 1: Clean build the whole app**

```bash
cd /Users/lantean/Developer/apple-browsers
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "macOS Browser" \
  -configuration Debug -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Confirm no stale references to the migrated string/symbols remain unswitched**

```bash
cd /Users/lantean/Developer/apple-browsers
echo "--- string ref must be gone ---"
grep -rn '"subscription-clock"' --include="*.swift" macOS/DuckDuckGo | grep -v ".build" || echo "none (good)"
echo "--- every new symbol should now sit beside a ternary/provider branch ---"
grep -rn "\.duckDuckGoResponseHeart\b\|\.historyBurn\b\|\.updatedBurnerWindowHome\b\|\.subscriptionClock96\b\|\.subscriptionClock\b\|\.bookmarksImport128\b" --include="*.swift" macOS/DuckDuckGo | grep -v ".build" | grep -v "Legacy"
```
Expected: string grep prints `none (good)`; each symbol line shows an `isAppRebranded ?` (or is the `CurrentIconsProvider` for fire).

- [ ] **Step 3: Visual smoke test — rebrand ON vs OFF**

Toggle the `appRebranding` feature flag (internal debug menu) and confirm each surface shows the new 2026 pictogram when ON and the prior art when OFF:
  1. Bookmark Manager empty state (no bookmarks) — `Bookmarks-Import`.
  2. Quit survey (positive) header — `DuckDuckGo-Response-Heart`.
  3. Fire dialog header — `Fire-128` (via `fireInfoGraphic`).
  4. Burner (fire) window new-tab header — `Fire-Window` (check both light & dark appearance).
  5. History delete dialog — `History-Burn`.
  6. Win-back new-tab promotion — `Subscription-Clock-96`.
  7. Win-back prompt sheet — `subscription-clock` (128).

Expected: correct art in both flag states on all 7 surfaces; dark-mode variant correct on #4.

- [ ] **Step 4: Report results to the owner** (no commit — leave changes staged in the working tree per Global Constraints).
