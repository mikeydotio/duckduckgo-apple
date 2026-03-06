# macOS Autoplay Blocking Settings — Design

**Date:** 2026-03-06
**Branch:** `juan/auto-block-videos`
**Reference:** iOS PR [#3840](https://github.com/duckduckgo/apple-browsers/pull/3840)

---

## Overview

Add a media autoplay blocking setting to macOS General preferences, under a new "Permissions" section. Users can choose from three policies applied to all newly created tabs via `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback`.

---

## UI

- Location: **Settings → General → Permissions** (new section, at the bottom of the pane)
- Row: label "Allow websites to autoplay" + `.menu` style `Picker` with three options:
  - **Video and audio** — allow all autoplay
  - **Video with audio muted** *(default)* — block audio autoplay only
  - **Never** — block all autoplay
- Footer: "Select ⓘ in the address bar to manage autoplay permissions for individual sites"

---

## Architecture

### Approach

New `AutoplayPreferences` model (Approach A) — dedicated model class following the existing macOS preferences pattern (same as `DuckPlayerPreferences`, `TabsPreferences`, etc.).

---

## Data Model & Storage

**New file:** `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`

- `AutoplayBlockingMode` enum: `String`, `CaseIterable`, `CustomStringConvertible`
  - `.allowAll` → "Video and audio"
  - `.blockAudio` → "Video with audio muted" *(default)*
  - `.blockAll` → "Never"
- Private extension mapping to `WKAudiovisualMediaTypes`:
  - `.allowAll → []`
  - `.blockAudio → .audio`
  - `.blockAll → .all`
- New `UserDefaults.Key`: `autoplayBlockingMode = "preferences.autoplay.blockingMode"`
- `AutoplayPreferences: ObservableObject` with `@UserDefaultsWrapper` storage

---

## Applying the Setting

**File:** `macOS/DuckDuckGo/Tab/Model/Tab.swift`

- Add `autoplayPreferences: AutoplayPreferences` parameter to `Tab.init()`
- After `configuration.applyStandardConfiguration(...)`, set:
  ```swift
  configuration.mediaTypesRequiringUserActionForPlayback = autoplayPreferences.autoplayBlockingMode.mediaTypesRequiringUserAction
  ```
- Setting applies to new tabs only (consistent with iOS and WebKit's behavior)
- `AutoplayPreferences` instance sourced from `Application.appDelegate`, passed in at Tab creation sites (`TabCollectionViewModel`, `WindowControllersManager`)

---

## UI Changes

**File:** `macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift`

- Add `@ObservedObject var autoplayModel: AutoplayPreferences` to `Preferences.GeneralView`
- New `PreferencePaneSection(UserText.permissionsSection)` at the bottom of the pane:
  ```swift
  HStack {
      Text(UserText.autoplayLabel)
      Picker("", selection: $autoplayModel.autoplayBlockingMode) {
          ForEach(AutoplayBlockingMode.allCases, id: \.self) { mode in
              Text(mode.description).tag(mode)
          }
      }
      .pickerStyle(.menu)
      .fixedSize()
  }
  ```
- `onChange` fires pixel `GeneralPixel.autoplaySettingChanged` with mode parameter

**File:** `macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift`

- Pass `autoplayModel: NSApp.delegateTyped.autoplayPreferences` to `GeneralView(...)`

**File:** `macOS/DuckDuckGo/Application/AppDelegate.swift` (or equivalent)

- Add `let autoplayPreferences = AutoplayPreferences()` alongside other shared preference singletons

---

## Pixels

**File:** `macOS/DuckDuckGo/Statistics/GeneralPixel.swift`

- `case autoplaySettingChanged` — fired on picker change, with parameter `autoplayBlockingMode: String` (raw value of the selected mode)

---

## Localization

**File:** `macOS/DuckDuckGo/Common/Localizables/UserText.swift`

| Key | Value |
|-----|-------|
| `permissionsSection` | "Permissions" |
| `autoplayLabel` | "Allow websites to autoplay" |
| `autoplayModeAllowAll` | "Video and audio" |
| `autoplayModeBlockAudio` | "Video with audio muted" |
| `autoplayModeBlockAll` | "Never" |
| `autoplayFooter` | "Select ⓘ in the address bar to manage autoplay permissions for individual sites" |

---

## Testing

- Unit tests in new `AutoplayPreferencesTests.swift`:
  - Default value is `.blockAudio`
  - Persistence round-trip (write/read from `UserDefaults`)
  - `AutoplayBlockingMode.mediaTypesRequiringUserAction` mapping correctness
- No UI snapshot tests (macOS preferences views don't use them)

---

## Files Changed

| File | Change |
|------|--------|
| `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift` | **New** |
| `macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift` | Add key |
| `macOS/DuckDuckGo/Tab/Model/Tab.swift` | Add parameter + apply setting |
| `macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift` | Add Permissions section |
| `macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift` | Pass model to GeneralView |
| `macOS/DuckDuckGo/Application/AppDelegate.swift` | Add shared AutoplayPreferences |
| `macOS/DuckDuckGo/Statistics/GeneralPixel.swift` | Add pixel |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` | Add strings |
| `macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift` | **New** |
