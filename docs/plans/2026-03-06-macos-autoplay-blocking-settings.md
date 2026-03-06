# macOS Autoplay Blocking Settings — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a media autoplay blocking setting to macOS General preferences under a new "Permissions" section, backed by `WKWebViewConfiguration.mediaTypesRequiringUserActionForPlayback`.

**Architecture:** New `AutoplayPreferences` model (protocol + struct persistor + ObservableObject) following the `DuckPlayerPreferences` pattern. The setting is applied in `Tab.init()` after `applyStandardConfiguration()`, and surfaced as a Picker in `PreferencesGeneralView`. Pixels fire in the model's `didSet`.

**Tech Stack:** Swift, AppKit, SwiftUI, WebKit, PixelKit, `@UserDefaultsWrapper`, `@Published`, Combine, XCTest

**Design doc:** `docs/plans/2026-03-06-macos-autoplay-blocking-settings-design.md`
**Reference:** iOS PR #3840 (`iOS/DuckDuckGo/AppSettings.swift`, `iOS/DuckDuckGo/AppUserDefaults.swift`, `iOS/DuckDuckGo/TabManager.swift`)

---

## Task 1: Add `UserDefaults.Key` and `AutoplayPreferences` model

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift` — add key to `UserDefaults.Key` enum
- Create: `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`

**Context:** `UserDefaults.Key` is a `String`-backed enum in `UserDefaultsWrapper.swift` around line 32. The `DuckPlayerPreferences.swift` file in the same directory is the exact pattern to follow — it has a protocol, a `@UserDefaultsWrapper` struct persistor, and an `ObservableObject` class with `@Published` properties that fire pixels in `didSet`.

**Step 1: Add the UserDefaults key**

In `macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift`, find the `enum Key: String, CaseIterable, StorageKeyDescribing` block (around line 51 where download keys live). Add:

```swift
case autoplayBlockingMode = "preferences.autoplay.blockingMode"
```

**Step 2: Create `AutoplayPreferences.swift`**

Create `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`:

```swift
//
//  AutoplayPreferences.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import PixelKit

enum AutoplayBlockingMode: String, CaseIterable, CustomStringConvertible {
    case allowAll
    case blockAudio
    case blockAll

    var description: String {
        switch self {
        case .allowAll: return UserText.autoplayModeAllowAll
        case .blockAudio: return UserText.autoplayModeBlockAudio
        case .blockAll: return UserText.autoplayModeBlockAll
        }
    }
}

protocol AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String { get set }
}

struct AutoplayPreferencesUserDefaultsPersistor: AutoplayPreferencesPersistor {
    @UserDefaultsWrapper(key: .autoplayBlockingMode, defaultValue: AutoplayBlockingMode.blockAudio.rawValue)
    var autoplayBlockingModeRawValue: String
}

final class AutoplayPreferences: ObservableObject {

    @Published var autoplayBlockingMode: AutoplayBlockingMode {
        didSet {
            persistor.autoplayBlockingModeRawValue = autoplayBlockingMode.rawValue
            switch autoplayBlockingMode {
            case .allowAll:
                PixelKit.fire(GeneralPixel.autoplaySettingAllowAll, doNotEnforcePrefix: true)
            case .blockAudio:
                PixelKit.fire(GeneralPixel.autoplaySettingBlockAudio, doNotEnforcePrefix: true)
            case .blockAll:
                PixelKit.fire(GeneralPixel.autoplaySettingBlockAll, doNotEnforcePrefix: true)
            }
        }
    }

    init(persistor: AutoplayPreferencesPersistor = AutoplayPreferencesUserDefaultsPersistor()) {
        self.persistor = persistor
        self.autoplayBlockingMode = AutoplayBlockingMode(rawValue: persistor.autoplayBlockingModeRawValue) ?? .blockAudio
    }

    private var persistor: AutoplayPreferencesPersistor
}
```

**Step 3: Add the new file to the Xcode project**

The project file at `macOS/DuckDuckGo/DuckDuckGo-macOS.xcodeproj/project.pbxproj` must include new Swift files. Open Xcode and add the new file to the `DuckDuckGo Privacy Browser` target under the `Preferences/Model` group. (Alternatively, run the build and fix any "file not found in target" errors by adding via Xcode.)

**Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift \
        macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift \
        macOS/DuckDuckGo/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "Add AutoplayPreferences model and UserDefaults key"
```

---

## Task 2: Add pixels

**Files:**
- Modify: `macOS/DuckDuckGo/Statistics/GeneralPixel.swift`

**Context:** `GeneralPixel` is a large enum with cases and a `name` computed property that returns pixel name strings. The DuckPlayer autoplay pixels are around line 170 / 833. The pattern is `case myPixel` in the enum, and `case .myPixel: return "m_mac_some_name"` in the `name` switch. Pixels used with `doNotEnforcePrefix: true` use their raw string as-is.

**Step 1: Add the three pixel cases**

Find the `case duckPlayerAutoplaySettingsOn` line (around line 170). Add the new cases nearby in the enum:

```swift
case autoplaySettingAllowAll
case autoplaySettingBlockAudio
case autoplaySettingBlockAll
```

**Step 2: Add name mappings**

Find the `case .duckPlayerAutoplaySettingsOn:` block in the `name` computed property (around line 833). Add:

```swift
case .autoplaySettingAllowAll:
    return "m_mac_autoplay_setting_allow-all"
case .autoplaySettingBlockAudio:
    return "m_mac_autoplay_setting_block-audio"
case .autoplaySettingBlockAll:
    return "m_mac_autoplay_setting_block-all"
```

**Step 3: Add to frequency/inclusion lists if required**

Search `GeneralPixel.swift` for arrays that list all pixels (e.g., around lines 1432 and 1585 — these look like test inclusion lists). Add the three new cases to any such arrays.

**Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Statistics/GeneralPixel.swift
git commit -m "Add autoplay blocking pixels"
```

---

## Task 3: Add localized strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`

**Context:** `UserText.swift` contains `static let` string properties using `NSLocalizedString`. Add these near the existing permissions-related strings (search for `permissionCenterTitle` around line 1093).

**Step 1: Add strings**

```swift
static let permissionsSection = NSLocalizedString("preferences.permissions.section", value: "Permissions", comment: "Section header for the Permissions section in General preferences")
static let autoplayLabel = NSLocalizedString("preferences.autoplay.label", value: "Allow websites to autoplay", comment: "Label for the autoplay blocking preference picker in General preferences")
static let autoplayModeAllowAll = NSLocalizedString("preferences.autoplay.mode.allow-all", value: "Video and audio", comment: "Autoplay mode: allow all media to autoplay")
static let autoplayModeBlockAudio = NSLocalizedString("preferences.autoplay.mode.block-audio", value: "Video with audio muted", comment: "Autoplay mode: allow video but block audio autoplay (default)")
static let autoplayModeBlockAll = NSLocalizedString("preferences.autoplay.mode.block-all", value: "Never", comment: "Autoplay mode: block all media autoplay")
```

**Step 2: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift
git commit -m "Add autoplay localized strings"
```

---

## Task 4: Write tests for `AutoplayPreferences`

**Files:**
- Create: `macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift`

**Context:** Tests live in `macOS/UnitTests/Preferences/`. They use a mock persistor struct and test via `XCTestCase`. See `DownloadsPreferencesTests.swift` for the pattern — create a mock persistor, initialize `AutoplayPreferences(persistor:)`, assert behavior. Add the test file to the Xcode test target.

**Step 1: Write the test file**

```swift
//
//  AutoplayPreferencesTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
import WebKit
@testable import DuckDuckGo_Privacy_Browser

struct AutoplayPreferencesPersistorMock: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
}

final class AutoplayPreferencesTests: XCTestCase {

    // MARK: - Default value

    func testDefaultModeIsBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    func testWhenPersistedValueIsInvalidThenDefaultsToBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: "invalidValue")
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    // MARK: - Persistence round-trip

    func testWhenModeIsSetThenPersistorIsUpdated() {
        var persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.autoplayBlockingMode = .allowAll
        // Re-read from a new instance initialized with the same persistor value
        // (direct persistor mutation check)
        XCTAssertEqual(prefs.autoplayBlockingMode, .allowAll)
    }

    func testAllModesRoundTrip() {
        for mode in AutoplayBlockingMode.allCases {
            let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: mode.rawValue)
            let prefs = AutoplayPreferences(persistor: persistor)
            XCTAssertEqual(prefs.autoplayBlockingMode, mode, "Round-trip failed for mode: \(mode)")
        }
    }

    // MARK: - WKAudiovisualMediaTypes mapping

    func testAllowAllMapsToEmptyMediaTypes() {
        XCTAssertEqual(AutoplayBlockingMode.allowAll.mediaTypesRequiringUserAction, [])
    }

    func testBlockAudioMapsToAudioOnly() {
        XCTAssertEqual(AutoplayBlockingMode.blockAudio.mediaTypesRequiringUserAction, .audio)
    }

    func testBlockAllMapsToAll() {
        XCTAssertEqual(AutoplayBlockingMode.blockAll.mediaTypesRequiringUserAction, .all)
    }

    // MARK: - objectWillChange

    func testObjectWillChangeFiresOnModeChange() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        let expectation = expectation(description: "objectWillChange fires")
        let cancellable = prefs.objectWillChange.sink { expectation.fulfill() }

        prefs.autoplayBlockingMode = .blockAll
        waitForExpectations(timeout: 0)
        withExtendedLifetime(cancellable) {}
    }
}
```

**Note:** The `mediaTypesRequiringUserAction` property tested here will be added in Task 5. The tests will compile after Task 5 is done. Add the file to Xcode's test target.

**Step 2: Commit**

```bash
git add macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift \
        macOS/DuckDuckGo/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "Add AutoplayPreferencesTests"
```

---

## Task 5: Apply setting in `Tab.init()`

**Files:**
- Modify: `macOS/DuckDuckGo/Tab/Model/Tab.swift`

**Context:** `Tab.swift` has two inits — a `convenience init` with optional parameters that falls back to `NSApp.delegateTyped.*` singletons, and a designated `init` where the actual work happens. The configuration is applied at line ~300:
```swift
let configuration = webViewConfiguration ?? WKWebViewConfiguration()
configuration.applyStandardConfiguration(...)
self.webViewConfiguration = configuration
```
You need to set `mediaTypesRequiringUserActionForPlayback` right after `applyStandardConfiguration`. Also add a `private extension AutoplayBlockingMode` at the bottom of `Tab.swift` mapping to `WKAudiovisualMediaTypes`.

**Step 1: Add `mediaTypesRequiringUserAction` mapping**

At the bottom of `macOS/DuckDuckGo/Tab/Model/Tab.swift`, add:

```swift
// MARK: - AutoplayBlockingMode + WebKit

private extension AutoplayBlockingMode {

    var mediaTypesRequiringUserAction: WKAudiovisualMediaTypes {
        switch self {
        case .allowAll: return []
        case .blockAudio: return .audio
        case .blockAll: return .all
        }
    }
}
```

**Step 2: Add `autoplayPreferences` to the convenience init**

In the convenience `init` parameter list (around line 115), add after `tabsPreferences: TabsPreferences? = nil`:

```swift
autoplayPreferences: AutoplayPreferences? = nil,
```

In the convenience init body where it calls `self.init(...)`, add after `tabsPreferences: tabsPreferences ?? NSApp.delegateTyped.tabsPreferences,`:

```swift
autoplayPreferences: autoplayPreferences ?? NSApp.delegateTyped.autoplayPreferences,
```

**Step 3: Add `autoplayPreferences` to the designated init**

In the designated `init` parameter list (around line 231), add after `tabsPreferences: TabsPreferences,`:

```swift
autoplayPreferences: AutoplayPreferences,
```

In the designated init body, find the configuration block (~line 300):

```swift
let configuration = webViewConfiguration ?? WKWebViewConfiguration()
configuration.applyStandardConfiguration(contentBlocking: privacyFeatures.contentBlocking,
                                         burnerMode: burnerMode,
                                         privateProcessName: featureFlagger.isFeatureOn(.privateProcessName),
                                         earlyAccessHandlers: specialPagesUserScript.map { [$0] } ?? [])
```

Add immediately after `applyStandardConfiguration(...)`:

```swift
configuration.mediaTypesRequiringUserActionForPlayback = autoplayPreferences.autoplayBlockingMode.mediaTypesRequiringUserAction
```

**Step 4: Verify the tests compile**

The tests in `AutoplayPreferencesTests.swift` reference `AutoplayBlockingMode.allowAll.mediaTypesRequiringUserAction`. Since this extension is `private` to `Tab.swift`, it won't be visible from tests. Move the extension to `AutoplayPreferences.swift` instead and make it `internal`:

In `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`, add at the bottom:

```swift
import WebKit

extension AutoplayBlockingMode {

    var mediaTypesRequiringUserAction: WKAudiovisualMediaTypes {
        switch self {
        case .allowAll: return []
        case .blockAudio: return .audio
        case .blockAll: return .all
        }
    }
}
```

And remove the `private extension AutoplayBlockingMode` block added to `Tab.swift` in Step 1 (since the extension now lives in `AutoplayPreferences.swift` and is visible everywhere).

**Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Tab/Model/Tab.swift \
        macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift
git commit -m "Apply autoplay blocking mode to WKWebViewConfiguration on tab creation"
```

---

## Task 6: Add `autoplayPreferences` to `AppDelegate`

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

**Context:** Around line 136-138 in `AppDelegate.swift`:
```swift
let downloadsPreferences: DownloadsPreferences
let searchPreferences: SearchPreferences
let tabsPreferences: TabsPreferences
```
And around line 769 in `applicationDidFinishLaunching`, `tabsPreferences` is initialized. Follow the exact same pattern.

**Step 1: Add the property declaration**

After `let tabsPreferences: TabsPreferences` (line ~138), add:

```swift
let autoplayPreferences: AutoplayPreferences
```

**Step 2: Initialize it**

Find where `tabsPreferences` is initialized (~line 769). Add immediately after:

```swift
autoplayPreferences = AutoplayPreferences()
```

**Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "Add autoplayPreferences singleton to AppDelegate"
```

---

## Task 7: Add Permissions section to General preferences UI

**Files:**
- Modify: `macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift`
- Modify: `macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift`

**Context:** `PreferencesGeneralView.swift` contains `Preferences.GeneralView: View`. It takes several `@ObservedObject` models. Add `autoplayModel` and a new "Permissions" section at the bottom of the pane (before the closing `}` of `PreferencePane`). In `PreferencesRootView.swift` around line 148, `GeneralView` is instantiated with named parameters — add `autoplayModel`.

**Step 1: Add model parameter to `GeneralView`**

In `Preferences.GeneralView`, add after the existing model properties:

```swift
@ObservedObject var autoplayModel: AutoplayPreferences
```

**Step 2: Add Permissions section**

In the `body` of `GeneralView`, after the last existing `PreferencePaneSection` (the `warnBeforeQuit` section), add:

```swift
// SECTION: Permissions
PreferencePaneSection(UserText.permissionsSection) {
    PreferencePaneSubSection {
        HStack {
            Picker(UserText.autoplayLabel, selection: $autoplayModel.autoplayBlockingMode) {
                ForEach(AutoplayBlockingMode.allCases, id: \.self) { mode in
                    Text(mode.description).tag(mode)
                }
            }
        }
    }
}
```

**Step 3: Pass model in `PreferencesRootView.swift`**

Find the `GeneralView(` call (around line 148) and add:

```swift
autoplayModel: NSApp.delegateTyped.autoplayPreferences,
```

**Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift \
        macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift
git commit -m "Add Permissions section with autoplay picker to General preferences"
```

---

## Task 8: Run tests and verify build

**Step 1: Build the macOS target in Xcode**

Open `macOS/DuckDuckGo/DuckDuckGo-macOS.xcodeproj` and build (`⌘B`). Fix any compilation errors.

**Step 2: Run `AutoplayPreferencesTests`**

In Xcode, run the `AutoplayPreferencesTests` test class. Expected: all tests pass.

**Step 3: Manual smoke test**

1. Launch the macOS app
2. Open Settings → General
3. Scroll to the new "Permissions" section
4. Verify the "Allow websites to autoplay" picker shows three options: "Video and audio", "Video with audio muted" (selected by default), "Never"
5. Change the selection — open a new tab and visit `https://privacy-test-pages.site/features/autoplay.html` to verify the policy applies
6. Quit and relaunch — verify the selection persists

**Step 4: Final commit**

If any small fixes were needed:

```bash
git add -p
git commit -m "Fix compilation issues from autoplay settings implementation"
```

---

## Summary of all changed files

| File | Change |
|------|--------|
| `macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift` | Add `autoplayBlockingMode` key |
| `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift` | **New** — enum, protocol, persistor, model |
| `macOS/DuckDuckGo/Statistics/GeneralPixel.swift` | Add 3 pixel cases + name mappings |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` | Add 5 localized strings |
| `macOS/DuckDuckGo/Application/AppDelegate.swift` | Add `autoplayPreferences` property + init |
| `macOS/DuckDuckGo/Tab/Model/Tab.swift` | Add param + apply `mediaTypesRequiringUserActionForPlayback` |
| `macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift` | Add `autoplayModel` + Permissions section |
| `macOS/DuckDuckGo/Preferences/View/PreferencesRootView.swift` | Pass `autoplayModel` to `GeneralView` |
| `macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift` | **New** — unit tests |
| `macOS/DuckDuckGo/DuckDuckGo-macOS.xcodeproj/project.pbxproj` | Add new files to targets |
