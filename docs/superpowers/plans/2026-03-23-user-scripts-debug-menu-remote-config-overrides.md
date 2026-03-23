# User Scripts Debug Menu — Remote Config Overrides Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Global section of `UserScriptsDebugMenu` with a mechanism that disables features by mutating the live privacy config JSON, so the real feature-gate code path is exercised.

**Architecture:** A new `PrivacyConfigOverrideStore` snapshots the config before the first override, patches it per-toggle via `JSONSerialization`, and calls `PrivacyConfigurationManager.reload(etag:data:)`. The menu enumerates feature keys dynamically from `currentConfig`. Per-tab disabling is unchanged.

**Tech Stack:** Swift, AppKit (`NSMenu`), `PrivacyConfig.PrivacyConfigurationManaging`, `Foundation.JSONSerialization`

**Spec:** `docs/superpowers/specs/2026-03-23-user-scripts-debug-menu-remote-config-overrides-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `macOS/DuckDuckGo/Debug/PrivacyConfigOverrideStore.swift` | **Create** | Owns override state; patches config JSON; calls `manager.reload` |
| `macOS/DuckDuckGo/Debug/UserScriptDisabledStore.swift` | **Delete** | Replaced by `PrivacyConfigOverrideStore` |
| `macOS/DuckDuckGo/Tab/UserScripts/UserScripts.swift` | **Modify** | Remove `UserScriptDisabledStore` reference from `loadWKUserScripts` |
| `macOS/DuckDuckGo/Debug/UserScriptsDebugMenu.swift` | **Modify** | Add `privacyConfigurationManager` init param; replace global section |
| `macOS/DuckDuckGo/Menus/MainMenu.swift` | **Modify** | Pass `privacyConfigurationManager` to `UserScriptsDebugMenu` |
| `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj` | **Modify** | Add `PrivacyConfigOverrideStore.swift`; remove `UserScriptDisabledStore.swift` |

---

## Task 1: Create `PrivacyConfigOverrideStore`

**Files:**
- Create: `macOS/DuckDuckGo/Debug/PrivacyConfigOverrideStore.swift`

`PrivacyConfigurationManaging` lives in the `PrivacyConfig` module (not `BrowserServicesKit`). Match the import pattern used by every other file that uses this protocol (e.g. `MainMenu.swift`, `ContentScopeExperimentsMenu.swift`).

Note on snapshot safety: `originalConfigData` is captured from `manager.currentConfig` on the first call to `disableFeature`. `currentConfig` returns `fetchedConfigData.rawData` when a fetched config is present, otherwise `embeddedConfigData.rawData`. The guard `if originalConfigData == nil` prevents re-capturing on subsequent calls — so as long as overrides are active the snapshot remains stable. A background network refresh could silently replace `fetchedConfigData` and drop all overrides, but this is an accepted limitation for a debug tool (documented in the spec edge cases table).

- [ ] **Step 1: Create the file**

```swift
//
//  PrivacyConfigOverrideStore.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PrivacyConfig

/// Session-only store for globally disabled ContentScope features via remote config override.
/// Disabling a feature patches the live privacy config JSON so the real feature-gate code path is exercised.
/// State resets on every app launch (no persistence).
@MainActor
final class PrivacyConfigOverrideStore {
    static let shared = PrivacyConfigOverrideStore()
    private init() {}

    private(set) var overriddenFeatures: Set<String> = []
    private var originalConfigData: Data?

    func disableFeature(_ key: String, in manager: PrivacyConfigurationManaging) {
        if originalConfigData == nil {
            originalConfigData = manager.currentConfig
        }
        overriddenFeatures.insert(key)
        applyOverrides(in: manager)
    }

    func enableFeature(_ key: String, in manager: PrivacyConfigurationManaging) {
        overriddenFeatures.remove(key)
        if overriddenFeatures.isEmpty {
            // reload(etag: nil, data: nil) always returns .embedded — no guard needed
            manager.reload(etag: nil, data: nil)
            originalConfigData = nil
        } else {
            applyOverrides(in: manager)
        }
    }

    // MARK: - Private

    private func applyOverrides(in manager: PrivacyConfigurationManaging) {
        guard let original = originalConfigData,
              var json = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any],
              var features = json["features"] as? [String: Any] else { return }

        for key in overriddenFeatures {
            if var feature = features[key] as? [String: Any] {
                feature["state"] = "disabled"
                features[key] = feature
            }
        }
        json["features"] = features

        guard let patchedData = try? JSONSerialization.data(withJSONObject: json) else { return }

        let result = manager.reload(etag: "debug-override", data: patchedData)
        if result == .embeddedFallback {
            // Patched JSON was rejected by the parser — reset to clean state
            overriddenFeatures = []
            originalConfigData = nil
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project**

In `project.pbxproj`, find the existing entries for `UserScriptDisabledStore.swift` (search for `UserScriptDisabledStore`). Add parallel entries for `PrivacyConfigOverrideStore.swift` in three places:
1. `PBXBuildFile` section — copy the UUID format from the `UserScriptDisabledStore` entry
2. `PBXFileReference` section — same
3. The `Debug` group's `children` array in `PBXGroup` — insert the new file reference UUID

Generate new UUIDs by running `uuidgen | tr -d '-' | head -c 24`.

- [ ] **Step 3: Build to confirm the file compiles cleanly**

Build the `DuckDuckGo` target. Expected: no errors in `PrivacyConfigOverrideStore.swift`. Other files are unchanged so the build is clean at this point.

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Debug/PrivacyConfigOverrideStore.swift macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add PrivacyConfigOverrideStore for privacy config JSON overrides"
```

---

## Task 2: Update `UserScripts.swift` and rewrite `UserScriptsDebugMenu.swift` (atomic)

**Files:**
- Modify: `macOS/DuckDuckGo/Tab/UserScripts/UserScripts.swift:277`
- Modify: `macOS/DuckDuckGo/Debug/UserScriptsDebugMenu.swift`

These two changes are committed together because removing the `UserScriptDisabledStore` reference from `UserScripts.swift` alone leaves `UserScriptsDebugMenu.swift` referencing a type that will shortly be deleted — splitting them creates an intermediate broken state.

- [ ] **Step 1: Update `UserScripts.swift` line 277**

Replace:
```swift
let disabled = perTabDisabled.union(UserScriptDisabledStore.shared.globallyDisabled)
```
with:
```swift
let disabled = perTabDisabled
```

- [ ] **Step 2: Replace `UserScriptsDebugMenu.swift` entirely**

```swift
//
//  UserScriptsDebugMenu.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import PrivacyConfig

/// Debug submenu for disabling individual user scripts per-tab or globally.
/// Per-tab changes filter scripts by debug name (session-only).
/// Global changes create a local privacy config override with the feature disabled (session-only).
@MainActor
final class UserScriptsDebugMenu: NSMenu, NSMenuDelegate {

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
        super.init(title: "Disable Individual Scripts")
        self.delegate = self
        self.autoenablesItems = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        removeAllItems()

        // Per-tab section
        let scriptNames = currentTabScriptNames()
        addSectionHeader("[Current Tab]")
        if scriptNames.isEmpty {
            let item = NSMenuItem(title: "No scripts loaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            addItem(item)
        } else {
            for name in scriptNames {
                let item = makeScriptItem(name: name,
                                          action: #selector(togglePerTab(_:)),
                                          isDisabled: currentTabUserScripts()?.perTabDisabled.contains(name) ?? false)
                addItem(item)
            }
        }

        addItem(.separator())

        // Global section — ContentScope features via remote config override
        // Checked state comes from overriddenFeatures (not from the "state" field in the config JSON,
        // which is already patched to "disabled" for overridden features).
        addSectionHeader("[Global — ContentScope features]")
        for name in contentScopeFeatureNames() {
            let item = makeScriptItem(name: name,
                                      action: #selector(toggleGlobal(_:)),
                                      isDisabled: PrivacyConfigOverrideStore.shared.overriddenFeatures.contains(name))
            addItem(item)
        }
    }

    private func addSectionHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    private func makeScriptItem(name: String, action: Selector, isDisabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
        item.representedObject = name
        item.target = self
        item.state = isDisabled ? .on : .off
        item.isEnabled = true
        return item
    }

    // MARK: - Helpers

    // trackerAllowlist/autoconsent: excluded by ContentScopePrivacyConfigurationJSONGenerator
    // macOSBrowserConfig/iOSBrowserConfig: native app feature flags, handled in Feature Flags debug menu
    private static let excludedFeatureKeys: Set<String> = [
        "trackerAllowlist",
        "autoconsent",
        "macOSBrowserConfig",
        "iOSBrowserConfig",
    ]

    private func contentScopeFeatureNames() -> [String] {
        guard let json = (try? JSONSerialization.jsonObject(with: privacyConfigurationManager.currentConfig)) as? [String: Any],
              let features = json["features"] as? [String: Any] else { return [] }
        return features.keys
            .filter { !Self.excludedFeatureKeys.contains($0) }
            .sorted()
    }

    private func currentTabUserScripts() -> UserScripts? {
        let tab = Application.appDelegate.windowControllersManager.selectedTab
        return tab?.userContentController?.contentBlockingAssets?.userScripts as? UserScripts
    }

    private func currentTabScriptNames() -> [String] {
        guard let scripts = currentTabUserScripts() else { return [] }
        return scripts.userScripts
            .map { $0.debugName }
            .sorted()
    }

    // MARK: - Actions

    @objc private func togglePerTab(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let tab = Application.appDelegate.windowControllersManager.selectedTab,
              let userScripts = tab.userContentController?.contentBlockingAssets?.userScripts as? UserScripts
        else { return }

        if userScripts.perTabDisabled.contains(name) {
            userScripts.perTabDisabled.remove(name)
        } else {
            userScripts.perTabDisabled.insert(name)
        }

        Task { @MainActor in
            await tab.userContentController?.reinstallUserScripts()
            tab.reload()
        }
    }

    @objc private func toggleGlobal(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }

        let store = PrivacyConfigOverrideStore.shared
        if store.overriddenFeatures.contains(name) {
            store.enableFeature(name, in: privacyConfigurationManager)
        } else {
            store.disableFeature(name, in: privacyConfigurationManager)
        }

        let allTabs = Application.appDelegate.windowControllersManager.mainWindowControllers
            .flatMap { wc -> [Tab] in
                let vm = wc.mainViewController.tabCollectionViewModel
                let regular = vm.tabCollection.tabs
                let pinned = vm.pinnedTabsCollection?.tabs ?? []
                return regular + pinned
            }

        Task { @MainActor in
            for tab in allTabs {
                await tab.userContentController?.reinstallUserScripts()
                tab.reload()
            }
        }
    }
}
```

- [ ] **Step 3: Build to confirm**

Build the target. Expected: errors only in `UserScriptDisabledStore.swift` — specifically, the `UserScriptDisabledStore` type now has no callers (its own file still compiles fine). After Task 3, `UserScriptDisabledStore.swift` will be deleted, clearing the build entirely.

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Tab/UserScripts/UserScripts.swift macOS/DuckDuckGo/Debug/UserScriptsDebugMenu.swift
git commit -m "feat: replace UserScriptsDebugMenu global section with remote config overrides"
```

---

## Task 3: Update `MainMenu.swift` call site

**Files:**
- Modify: `macOS/DuckDuckGo/Menus/MainMenu.swift:849`

`MainMenu` already stores `self.privacyConfigurationManager: PrivacyConfigurationManaging` — no init changes needed.

- [ ] **Step 1: Update the call site**

Find line 849:
```swift
.submenu(UserScriptsDebugMenu())
```

Replace with:
```swift
.submenu(UserScriptsDebugMenu(privacyConfigurationManager: privacyConfigurationManager))
```

- [ ] **Step 2: Build to confirm**

Build the target. Expected: no errors in `MainMenu.swift`. The only remaining compile issue is `UserScriptDisabledStore.swift` being present but unused — deleted in the next task.

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Menus/MainMenu.swift
git commit -m "chore: pass privacyConfigurationManager to UserScriptsDebugMenu"
```

---

## Task 4: Delete `UserScriptDisabledStore`

**Files:**
- Delete: `macOS/DuckDuckGo/Debug/UserScriptDisabledStore.swift`
- Modify: `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Delete the file**

```bash
git rm macOS/DuckDuckGo/Debug/UserScriptDisabledStore.swift
```

- [ ] **Step 2: Remove from `project.pbxproj`**

Search `project.pbxproj` for `UserScriptDisabledStore`. Remove:
1. Its `PBXBuildFile` entry
2. Its `PBXFileReference` entry
3. Its UUID reference in the `Debug` group's `children` array in `PBXGroup`

- [ ] **Step 3: Build to confirm**

Build the target. Expected: clean build with zero errors.

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "chore: delete UserScriptDisabledStore — replaced by PrivacyConfigOverrideStore"
```

---

## Task 5: Smoke test

- [ ] Launch the app in debug mode. Open **Debug > User Scripts > Disable Individual Scripts**.

- [ ] Verify `[Current Tab]` section lists the same scripts as before (e.g. `ContentScopeUserScript`, `ContentScopeUserScriptIsolated`, `AutofillScript`). Toggling one reloads the tab and that script is no longer injected.

- [ ] Verify `[Global — ContentScope features]` lists feature keys from the live config sorted alphabetically. Confirm `trackerAllowlist`, `autoconsent`, `macOSBrowserConfig`, `iOSBrowserConfig` are absent.

- [ ] Toggle a feature (e.g. `fingerprintingCanvas`). Checkmark appears. All tabs reload. Open the privacy dashboard on any site — the feature should show as disabled.

- [ ] Toggle the same feature again. Checkmark disappears. All tabs reload. Feature is active again.

- [ ] Disable two features. Both checkmarks appear. Re-enable one. The other remains checked and disabled in the config.
