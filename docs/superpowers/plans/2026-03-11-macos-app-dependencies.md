# macOS AppDependencies Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all dependency creation from `AppDelegate.init()` into the `Launching` state, wrapped in an `AppDependencies` container.

**Architecture:** `Launching` becomes a class that creates all ~89 dependencies in its `init()`. It builds an `AppDependencies` struct with grouped sub-containers (Stores, FeatureFlags, Preferences, Services, UI, Subscription) and passes it to `Foreground`. AppDelegate becomes a thin shell with forwarding computed properties for backward compatibility.

**Tech Stack:** Swift, AppKit, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-11-macos-app-dependencies-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `macOS/DuckDuckGo/Application/AppLifecycle/AppDependencies.swift` | Create | AppDependencies struct with sub-container types |
| `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift` | Rewrite | Class that creates all dependencies, builds AppDependencies |
| `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Initializing.swift` | Modify | Remove AppDelegate ref, add crash handler setup |
| `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Foreground.swift` | Modify | Hold AppDependencies instead of weak AppDelegate |
| `macOS/DuckDuckGo/Application/AppDelegate.swift` | Modify | Strip init body, add forwarding properties |
| `macOS/UnitTests/AppLifecycle/AppStateMachineTests.swift` | Verify | Confirm existing mocks still conform to protocols |

---

## Chunk 1: Skeleton, Launching, Initializing, and AppDelegate Shell

### Task 1: Create AppDependencies struct

**Files:**
- Create: `macOS/DuckDuckGo/Application/AppLifecycle/AppDependencies.swift`

- [ ] **Step 1: Create AppDependencies.swift with all sub-containers**

The sub-containers group the ~89 properties. Each sub-container is a struct with `let` properties (or `var` where mutability is needed). `AppDependencies` itself is a struct holding all sub-containers.

Reference the current property declarations in `AppDelegate.swift:66-414` to determine exact types. Here is the container structure:

```swift
//
//  AppDependencies.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  ...
//

// Import all modules needed for the property types.
// Copy the import block from AppDelegate.swift and trim to what's actually used.

struct AppDependencies {

    let stores: Stores
    let featureFlags: FeatureFlags
    let preferences: Preferences
    let services: Services
    let ui: UI
    let subscription: SubscriptionDependencies

}
```

Each sub-container is defined as a nested type inside `AppDependencies` (or at file scope — match codebase convention). The properties per sub-container, with types taken from `AppDelegate.swift:66-414`:

**Stores:** `keyStore`, `keyValueStore`, `fileStore`, `database`, `bookmarkDatabase`, `configurationStore` — match types exactly from AppDelegate declarations.

**FeatureFlags:** `featureFlagger`, `internalUserDecider`, `contentScopeExperimentsManager`, `featureFlagOverridesPublishingHandler`

**Preferences:** All ~13 preference objects: `appearancePreferences`, `dataClearingPreferences`, `startupPreferences`, `defaultBrowserPreferences`, `downloadsPreferences`, `searchPreferences`, `tabsPreferences`, `webTrackingProtectionPreferences`, `cookiePopupProtectionPreferences`, `aboutPreferences`, `accessibilityPreferences`, `contentScopePreferences`, `aiChatPreferences`

**Services:** All managers, coordinators, handlers — including `updateController` (used by termination deciders): `configurationManager`, `configurationURLProvider`, `bookmarkManager`, `historyCoordinator`, `faviconManager`, `fireproofDomains`, `permissionManager`, `downloadManager`, `downloadListCoordinator`, `privacyStats`, `autoconsentStats`, `remoteMessagingClient`, `activeRemoteMessageModel`, `syncService`, `syncDataProviders`, `syncErrorHandler`, `webCacheManager`, `crashReporting`, `watchdog`, `watchdogSleepMonitor`, `autoClearHandler`, `privacyFeatures`, `tld`, `autoconsentManagement`, `brokenSitePromptLimiter`, `notificationService`, `onboardingContextualDialogsManager`, `defaultBrowserAndDockPromptService`, `userChurnScheduler`, `bitwardenManager`, `passwordManagerCoordinator`, `attributedMetricManager`, `memoryUsageMonitor`, `memoryUsageThresholdReporter`, `memoryPressureReporter`, `memoryUsageIntervalReporter`, `startupProfiler`, `duckPlayer`, `newTabPageCustomizationModel`, `vpnSettings`, `freemiumDBPFeature`, `freemiumDBPPromotionViewCoordinator`, `blackFridayCampaignProvider`, `wideEvent`, `urlEventHandler`, `tabCrashAggregator`, `grammarFeaturesManager`, `webExtensionAvailability`, `aiChatSessionStore`, `aiChatMenuConfiguration`, `visualizeFireSettingsDecider`, `autoconsentEventCoordinator`, `stateRestorationManager`, `appIconChanger`, `launchOptionsHandler`, `updateController`

**UI:** `windowControllersManager`, `pinnedTabsManager`, `pinnedTabsManagerProvider`, `themeManager`, `fireCoordinator`, `recentlyClosedCoordinator`, `tabDragAndDropManager`, `bookmarkDragDropManager`, `pinningManager`

**SubscriptionDependencies:** `subscriptionManager`, `subscriptionUIHandler`, `subscriptionNavigationCoordinator`, `freeTrialConversionService`

Note: Some properties may need to be `var` in the sub-container (e.g., `syncService: DDGSyncing?`, `autoClearHandler: AutoClearHandler!`). Match optionality and access patterns from AppDelegate.

- [ ] **Step 2: Add the file to the Xcode project**

Use Xcode MCP or manually add to `DuckDuckGo-macOS.xcodeproj` under the `AppLifecycle` group.

- [ ] **Step 3: Build to verify the file compiles**

Run: Build via Xcode MCP
Expected: BUILD SUCCEEDED (the struct is not yet used)

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppDependencies.swift
git commit -m "Add AppDependencies struct with sub-container types"
```

### Task 2: Convert Launching to a class and move init body

This is the core task. Move the entire `AppDelegate.init()` body (lines 417-1166) into `Launching.init()`.

**Files:**
- Rewrite: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift`

- [ ] **Step 1: Rewrite Launching as a class**

`Launching` becomes a `final class` that:
1. Creates all dependencies in `init() throws` — copy the init body from `AppDelegate.init()` (lines 424-1165), with these adjustments:
   - Remove crash handler setup (lines 434-446) — moves to Initializing (Task 3)
   - Remove `self.dockCustomization = dockCustomization` (stays on AppDelegate)
   - Remove `super.init()` call — this is not an NSObject subclass
   - Convert `fatalError` calls to `throw` for database and key-value store failures
   - Self-capturing closures (memoryPressureReporter, memoryUsageIntervalReporter) work naturally in a class via two-phase init
   - `appContentBlocking?.userContentUpdating.userScriptDependenciesProvider = self` — AppDelegate can set this after Launching completes, via forwarding
   - Preserve all `#if DEBUG` conditional compilation blocks exactly
   - Preserve `.unitTests`/`.integrationTests`/`.xcPreviews` branching
2. Builds `AppDependencies` from the created properties
3. Stores `AppDependencies` as a property
4. `makeForegroundState()` creates `Foreground(dependencies:)`

This step is large (~740 lines of init code). Work through it methodically following the dependency order: database → stores → feature flags → preferences → managers → coordinators → UI. All properties become local `let`/`var` in the init, then assembled into `AppDependencies` at the end.

Key structure:

```swift
@MainActor
final class Launching: LaunchingHandling {

    let dependencies: AppDependencies

    init() throws {
        let startupProfiler = StartupProfiler()
        let profilerToken = startupProfiler.startMeasuring(.appDelegateInit)
        defer { profilerToken.stop() }

        // Copy AppDelegate.init() lines 447-1165 here (skip 434-446 crash handlers)
        // Follow dependency order: database → stores → feature flags → preferences → managers → coordinators → UI
        // Replace fatalError() with throw for KVS/database failures
        // All properties are local variables assembled into AppDependencies at the end

        // Build AppDependencies
        self.dependencies = AppDependencies(
            stores: .init(keyStore: keyStore, keyValueStore: keyValueStore, ...),
            featureFlags: .init(featureFlagger: featureFlagger, ...),
            preferences: .init(appearancePreferences: appearancePreferences, ...),
            services: .init(configurationManager: configurationManager, updateController: updateController, ...),
            ui: .init(windowControllersManager: windowControllersManager, ...),
            subscription: .init(subscriptionManager: subscriptionManager, ...)
        )
    }

    func makeForegroundState() throws -> any ForegroundHandling {
        Foreground(dependencies: dependencies)
    }

}
```

**Important notes:**
- The `WebExtensionManagerHolder` pattern (AppDelegate lines 372-379) references `self` (AppDelegate). For now, create `webExtensionAvailability` with a closure capturing Launching's local scope, or bridge via AppDelegate forwarding.
- `Application.appDelegate.xxx` references in closures within init (e.g., `fireCoordinator`'s `onboardingContextualDialogsManager` closure at line 845) continue to work through AppDelegate forwarding properties (added in Task 4).
- Properties that were `lazy var` on AppDelegate and are now needed eagerly should be created at the point where all their dependencies are available.

- [ ] **Step 2: Build to verify Launching compiles**

Run: Build via Xcode MCP
Expected: May have compilation errors — fix import issues, type mismatches. Iterate until BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift
git commit -m "Move dependency creation from AppDelegate.init() to Launching"
```

### Task 3: Update Initializing and state transition timing

This must happen before stripping AppDelegate (Task 4) because after Task 2, `Launching(appDelegate:)` no longer exists — `Initializing.makeLaunchingState()` must be updated to call `try Launching()`.

**Critical timing issue:** `applicationWillFinishLaunching` (lines 1173-1224) accesses many properties (`startupProfiler`, `keyValueStore`, `fileStore`, `startupPreferences`, `stateRestorationManager`, `subscriptionManager`, `pinningManager`, `freemiumDBPFeature`, etc.) AFTER `handle(.willFinishLaunching)` but BEFORE `handle(.didFinishLaunching)` which creates Launching. If those properties become forwarding-only, they'd crash because the state machine is still in `.initializing` and `AppDependencies` doesn't exist yet.

**Fix:** Move `handle(.didFinishLaunching)` from `applicationDidFinishLaunching` into `applicationWillFinishLaunching`, right after `handle(.willFinishLaunching)`. This creates Launching (with all dependencies) before any property access in `applicationWillFinishLaunching`. The state machine transitions become:
1. `handle(.willFinishLaunching)` → Initializing does crash setup, stays in `.initializing`
2. `handle(.didFinishLaunching)` → transitions to `.launching`, creates all dependencies
3. Rest of `applicationWillFinishLaunching` code runs with properties available via forwarding
4. `applicationDidFinishLaunching` no longer dispatches a state machine event

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Initializing.swift`
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

- [ ] **Step 1: Remove AppDelegate dependency, add crash handler setup**

Replace the entire `Initializing.swift` content with:

```swift
//
//  Initializing.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  ...
//

import Common
import Crashes
import Foundation
import PixelKit

@MainActor
struct Initializing: InitializingHandling {

    init() {}

    func handleWillFinishLaunching() {
        let didCrashDuringCrashHandlersSetUp = UserDefaultsWrapper(key: .didCrashDuringCrashHandlersSetUp, defaultValue: false)
        if case .normal = AppVersion.runType,
           !didCrashDuringCrashHandlersSetUp.wrappedValue {
            didCrashDuringCrashHandlersSetUp.wrappedValue = true
            CrashLogMessageExtractor.setUp(swapCxaThrow: false)
            didCrashDuringCrashHandlersSetUp.wrappedValue = false
        }

        if AppVersion.runType.requiresEnvironment {
            AppDelegate.configurePixelKit()
        }
    }

    func makeLaunchingState() throws -> any LaunchingHandling {
        try Launching()
    }

}
```

Note: `mutating` is removed from `handleWillFinishLaunching()` since the struct no longer has mutable state. The `InitializingHandling` protocol declares it as `mutating` which is compatible with non-mutating implementations. Imports for `Crashes` (for `CrashLogMessageExtractor`), `PixelKit`, and `Common` (for `UserDefaultsWrapper` / `AppVersion`) may need adjustment — verify against the actual module locations.

- [ ] **Step 2: Update AppDelegate state machine event dispatch timing**

In `AppDelegate.applicationWillFinishLaunching` (around line 1170-1171), change to dispatch both events:
```swift
// Before:
appStateMachine = AppStateMachine(initialState: .initializing(Initializing(appDelegate: self)))
appStateMachine.handle(.willFinishLaunching)

// After:
appStateMachine = AppStateMachine(initialState: .initializing(Initializing()))
appStateMachine.handle(.willFinishLaunching)
appStateMachine.handle(.didFinishLaunching)
// State is now .launching — all dependencies available via forwarding properties
```

In `AppDelegate.applicationDidFinishLaunching` (around line 1228), remove the state machine event dispatch:
```swift
// Remove this line:
appStateMachine.handle(.didFinishLaunching)
```

The rest of `applicationDidFinishLaunching` remains unchanged — it accesses properties via forwarding which works because the state machine is in `.launching`.

- [ ] **Step 3: Build and verify**

Run: Build via Xcode MCP
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Initializing.swift macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "Update Initializing and move didFinishLaunching dispatch to willFinishLaunching"
```

### Task 4: Strip AppDelegate.init() and add forwarding properties

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

- [ ] **Step 1: Replace AppDelegate.init() body**

Replace the init body (lines 417-1166) with a minimal version:

```swift
init(dockCustomization: DockCustomization?) {
    self.dockCustomization = dockCustomization
    super.init()
}
```

- [ ] **Step 2: Remove all property declarations that moved to Launching**

Remove the stored property declarations (lines 82-414) that are now in AppDependencies. Keep:
- `appStateMachine: AppStateMachine!`
- `didFinishLaunching: Bool`
- `dockCustomization: DockCustomization?`
- `@UserDefaultsWrapper private var didCrashDuringCrashHandlersSetUp: Bool` (used in `applicationDidFinishLaunching` at line 1345)
- `lazy var` UI coordinators (these stay for now)
- `@IBAction` related state
- `automationServer` (if needed for lifecycle callbacks not yet migrated)
- Static properties (`firstLaunchDate`, `isNewUser`, etc.)
- Cancellables that are set up during `applicationDidFinishLaunching` (not in init)
- Any `@objc` properties referenced by XIB/storyboard bindings

- [ ] **Step 3: Add `appDependencies` computed property**

Add a way to access AppDependencies from the state machine:

```swift
private var appDependencies: AppDependencies {
    // Force-cast is intentional: only real Launching/Foreground are in the state machine
    // at runtime. Test code uses mock types at the protocol level and never reaches this path.
    switch appStateMachine.currentState {
    case .launching(let launching):
        return (launching as! Launching).dependencies
    case .foreground(let foreground):
        return (foreground as! Foreground).dependencies
    default:
        fatalError("AppDependencies accessed before Launching state")
    }
}
```

- [ ] **Step 4: Add forwarding computed properties**

For every property that external code accesses via `Application.appDelegate.xxx` or `NSApp.delegateTyped.xxx`, add a forwarding property:

```swift
// MARK: - Forwarding Properties (backward compatibility)

var keyValueStore: ThrowingKeyValueStoring { appDependencies.stores.keyValueStore }
var featureFlagger: FeatureFlagger { appDependencies.featureFlags.featureFlagger }
var windowControllersManager: WindowControllersManager { appDependencies.ui.windowControllersManager }
var downloadManager: DownloadManager { appDependencies.services.downloadManager }
var updateController: UpdateController? { appDependencies.services.updateController }
// ... etc. for every externally-accessed property
```

Use `Grep` to find all `appDelegate.xxx` and `delegateTyped.xxx` references across the codebase to determine which properties need forwarding. Also add forwarding for properties accessed by the `lazy var` UI coordinators still on AppDelegate.

- [ ] **Step 5: Update `lazy var` properties to use forwarding access**

The `lazy var` UI coordinators on AppDelegate (e.g., `newTabPageCoordinator`, `vpnUpsellPopoverPresenter`, etc.) reference properties that moved. Update them to use the forwarding properties (which they already do implicitly since they reference `self.xxx`). Verify each `lazy var` still compiles.

- [ ] **Step 6: Build and fix all compilation errors**

Run: Build via Xcode MCP
Expected: Likely many errors. Fix iteratively:
- Missing property errors → add forwarding property or adjust reference
- Type mismatches → check sub-container access path
- Access control → widen as needed

Iterate until BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "Strip AppDelegate.init(), add forwarding properties for backward compat"
```

---

## Chunk 2: Update Foreground and Tests

### Task 5: Update Foreground to use AppDependencies

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Foreground.swift`

- [ ] **Step 1: Replace weak AppDelegate with AppDependencies**

Replace the `init` and property declarations:

```swift
@MainActor
final class Foreground: ForegroundHandling {

    let dependencies: AppDependencies
    private var terminationHandler: TerminationDeciderHandler?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // onTransition() and didReturn() unchanged
```

- [ ] **Step 2: Rewrite `createTerminationDeciders()` with AppDependencies**

Replace the method with all `appDelegate.xxx` references mapped to `dependencies.xxx`. The `guard let appDelegate else { return [] }` guard is removed since `dependencies` is a non-optional `let`. Closures that previously captured `[weak appDelegate]` now capture `[weak self]` (Foreground is a class):

```swift
private func createTerminationDeciders() -> [ApplicationTerminationDecider] {
    let persistor = QuitSurveyUserDefaultsPersistor(keyValueStore: dependencies.stores.keyValueStore)

    let deciders: [ApplicationTerminationDecider?] = [
        QuitSurveyAppTerminationDecider(
            featureFlagger: dependencies.featureFlags.featureFlagger,
            dataClearingPreferences: dependencies.preferences.dataClearingPreferences,
            downloadManager: dependencies.services.downloadManager,
            installDate: AppDelegate.firstLaunchDate,
            persistor: persistor,
            reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: dependencies.stores.keyValueStore),
            showQuitSurvey: { [weak self] in
                guard let self else { return }
                let presenter = QuitSurveyPresenter(
                    windowControllersManager: self.dependencies.ui.windowControllersManager,
                    persistor: persistor
                )
                await presenter.showSurvey()
            }
        ),

        ActiveDownloadsAppTerminationDecider(
            downloadManager: dependencies.services.downloadManager,
            downloadListCoordinator: dependencies.services.downloadListCoordinator
        ),

        makeWarnBeforeQuitDecider(),

        .perform { [weak self] in
            self?.dependencies.services.updateController?.handleAppTermination()
        },

        .perform { [weak self] in
            self?.dependencies.services.stateRestorationManager?.applicationWillTerminate()
        },

        dependencies.services.autoClearHandler,

        .terminationDecider { [weak self] _ in
            guard let self else { return .sync(.next) }
            return .async(Task {
                await self.dependencies.services.privacyStats.handleAppTermination()
                return .next
            })
        },

        .perform {
            NSApp.visibleWindows.forEach { $0.close() }
        }
    ]

    return deciders.compactMap { $0 }
}
```

- [ ] **Step 3: Rewrite `makeWarnBeforeQuitDecider()` with AppDependencies**

Replace the method. The `guard let appDelegate else { return nil }` guard is removed:

```swift
private func makeWarnBeforeQuitDecider() -> ApplicationTerminationDecider? {
    let willShowAutoClearWarning = dependencies.preferences.dataClearingPreferences.isAutoClearEnabled
        && dependencies.preferences.dataClearingPreferences.isWarnBeforeClearingEnabled

    let hasWindow = dependencies.ui.windowControllersManager.lastKeyMainWindowController?.window != nil

    guard dependencies.featureFlags.featureFlagger.isFeatureOn(.warnBeforeQuit),
          !willShowAutoClearWarning,
          hasWindow,
          let currentEvent = NSApp.currentEvent else { return nil }

    guard let manager = WarnBeforeQuitManager(
        currentEvent: currentEvent,
        action: .quit,
        isWarningEnabled: { [weak self] in
            self?.dependencies.preferences.tabsPreferences.warnBeforeQuitting ?? false
        },
        isPhysicalKeyPress: WarnBeforeQuitManager.makePhysicalKeyPressCheck(for: currentEvent)
    ) else { return nil }

    let presenter = WarnBeforeQuitOverlayPresenter(
        startupPreferences: dependencies.preferences.startupPreferences,
        buttonHandlers: [.dontShowAgain: { [weak self] in
            PixelKit.fire(GeneralPixel.warnBeforeQuitDontShowAgain, frequency: .standard)
            self?.dependencies.preferences.tabsPreferences.warnBeforeQuitting = false
        }],
        onHoverChange: { [weak manager] isHovering in
            manager?.setMouseHovering(isHovering)
        }
    )

    presenter.subscribe(to: manager.stateStream)
    return manager
}
```

- [ ] **Step 4: Build and verify**

Run: Build via Xcode MCP
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Foreground.swift
git commit -m "Update Foreground to use AppDependencies instead of AppDelegate ref"
```

### Task 6: Update tests and verify

**Files:**
- Verify: `macOS/UnitTests/AppLifecycle/AppStateMachineTests.swift`

- [ ] **Step 1: Verify MockInitializing matches protocol**

The current `MockInitializing` in the test file (lines 27-45) already has `init() {}` and uses `func handleWillFinishLaunching()` (non-mutating, which is compatible). Since the `InitializingHandling` protocol's `handleWillFinishLaunching()` is declared `mutating`, class implementations can use non-mutating. Verify no changes needed.

- [ ] **Step 2: Run all AppStateMachine tests**

Run: via Xcode MCP RunSomeTests — all 19 tests in `AppStateMachineTests.swift`
Expected: All pass. The mock types don't interact with AppDependencies.

- [ ] **Step 3: Run existing TerminationDeciderHandler tests**

Run: via Xcode MCP RunSomeTests — TerminationDeciderHandlerTests
Expected: All pass.

- [ ] **Step 4: Build and run the app for smoke test**

Verify:
- App launches normally
- Can browse pages
- Cmd+Q triggers termination flow (quit survey, warn before quit, etc.)
- No crashes or unexpected behavior

- [ ] **Step 5: Commit (if changes were needed)**

If any adjustments were needed to the test file, commit them:
```bash
git add macOS/UnitTests/AppLifecycle/AppStateMachineTests.swift
git commit -m "Phase 2 Sub-project 1: adjust tests for AppDependencies migration"
```

No commit expected if tests pass without modification — the mock types operate at the protocol level and should be unaffected.
