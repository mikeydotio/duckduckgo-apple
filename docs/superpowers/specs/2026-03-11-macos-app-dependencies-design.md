# macOS AppDependencies — Phase 2 Sub-project 1 Design Spec

## Goal

Move all dependency creation out of `AppDelegate.init()` into the `Launching` state handler, wrapped in a structured `AppDependencies` container. This mirrors the iOS pattern and is the foundation for migrating lifecycle logic in subsequent sub-projects.

## Context

AppDelegate currently owns ~89 properties created in its `init()`. These range from low-level stores to UI managers. The state machine (Phase 1) and termination handling (Phase 3) are already in place. This sub-project extracts dependency creation so that:

- `Initializing` handles only crash handler setup and PixelKit configuration
- `Launching` creates all dependencies and wraps them in `AppDependencies`
- `Foreground` receives `AppDependencies` instead of holding a weak AppDelegate reference
- AppDelegate becomes a thin shell with forwarding properties for backward compatibility

## Architecture

### AppDependencies Structure

`AppDependencies` is a struct with grouped sub-containers:

```
AppDependencies
├── Stores        — keyStore, keyValueStore, fileStore, database, bookmarkDatabase, configurationStore
├── Preferences   — tabsPreferences, startupPreferences, dataClearingPreferences, searchPreferences,
│                   appearancePreferences, accessibilityPreferences, downloadsPreferences,
│                   defaultBrowserPreferences, aboutPreferences, contentScopePreferences,
│                   webTrackingProtectionPreferences, cookiePopupProtectionPreferences, aiChatPreferences
├── FeatureFlags  — featureFlagger, internalUserDecider, contentScopeExperimentsManager
├── Services      — configurationManager, bookmarkManager, historyCoordinator,
│                   faviconManager, fireproofDomains, permissionManager, downloadManager,
│                   downloadListCoordinator, privacyStats, remoteMessagingClient,
│                   activeRemoteMessageModel, syncService, syncDataProviders, webCacheManager,
│                   crashReporting, watchdog, autoClearHandler, etc.
├── UI            — windowControllersManager, pinnedTabsManager, pinnedTabsManagerProvider,
│                   themeManager, fireCoordinator, duckPlayer, newTabPageCustomizationModel,
│                   recentlyClosedCoordinator, tabDragAndDropManager, bookmarkDragDropManager
└── Subscription  — subscriptionManager, subscriptionUIHandler,
                    subscriptionNavigationCoordinator, freeTrialConversionService
```

The exact property-to-container mapping is a planning deliverable — the first task in the implementation plan will finalize the groupings by categorizing every property.

### Launching: Class, Not Struct

`Launching` becomes a `final class` (not a struct). Reasons:

- Several properties require self-capturing closures during initialization (e.g., `memoryPressureReporter`, `memoryUsageIntervalReporter`, `vpnUpsellVisibilityManager`). A class supports two-phase initialization: assign stored properties first, then set up self-referencing subscriptions.
- `Launching` holds ~89 properties — copying a struct of this size on every mutation would be wasteful.
- Matches `Foreground`, which is already a class (changed in Phase 3).

### Error Handling in Launching

`Launching.init()` is throwing, matching the iOS pattern. The current `AppDelegate.init()` has `fatalError` paths (database load failure, key-value store failure). These become thrown errors, which the state machine already handles — `respond(to:in: initializing)` catches errors from `makeLaunchingState()` and transitions to `Terminating`.

The `LaunchingHandling` protocol already declares `makeForegroundState() throws`. Similarly, `InitializingHandling.makeLaunchingState() throws`. So `Initializing.makeLaunchingState()` calls `try Launching()`, and failures flow naturally to the Terminating state.

### State Flow

```
Initializing                    Launching                       Foreground
─────────────                   ─────────────                   ──────────
- Crash handler setup           - Creates all dependencies      - Holds AppDependencies
- PixelKit configuration        - Builds AppDependencies        - Uses it for termination
- No access to AppDependencies  - Passes to Foreground            deciders and all services
                                  via makeForegroundState()
```

- **Initializing.handleWillFinishLaunching()**: Sets up crash handlers (lines 434-442 of current AppDelegate) and configures PixelKit. No dependency creation. Self-contained — no AppDelegate reference needed.
- **Initializing.makeLaunchingState()**: Creates `Launching()` (no AppDelegate parameter). Throws if dependency creation fails.
- **Launching.init()**: Creates all dependencies following the same ordering as today's `AppDelegate.init()` (database → stores → feature flags → managers → coordinators). Wraps everything in `AppDependencies`. Throws on critical failures (database, key-value store).
- **Launching.makeForegroundState()**: Creates `Foreground(dependencies:)` with `AppDependencies`.
- **Foreground**: Drops `weak var appDelegate: AppDelegate?`. Holds `AppDependencies` instead. Termination decider chain (Phase 3) reads from `AppDependencies` fields.
- **Terminating**: No change.

### Protocol Changes

Protocol signatures are unchanged:

- `InitializingHandling.makeLaunchingState() throws -> any LaunchingHandling` — already supports throwing
- `LaunchingHandling.makeForegroundState() throws -> any ForegroundHandling` — unchanged
- `ForegroundHandling` — unchanged

How `Launching` passes `AppDependencies` to `Foreground` is an implementation detail, not a protocol concern.

### Wiring: How Initializing Creates Launching

Currently `Initializing.makeLaunchingState()` creates `Launching(appDelegate:)`. After migration:

```swift
func makeLaunchingState() throws -> any LaunchingHandling {
    return try Launching()
}
```

`Initializing` becomes fully self-contained — no AppDelegate reference. The `init(appDelegate:)` initializer and the `weak var appDelegate` property are removed.

### AppDelegate After Migration

AppDelegate becomes a thin shell:

- **Keeps:** `appStateMachine`, lifecycle callback routing (thin one-liners), `@IBAction` methods, menu handling
- **Adds:** `appDependencies` computed property (reads from state machine's current Launching/Foreground state), forwarding computed properties for backward compatibility (e.g., `var featureFlagger: FeatureFlagger { appDependencies.featureFlags.featureFlagger }`)
- **Removes:** All ~89 property declarations and `init()` body (except `super.init()`)
- **`lazy var` UI coordinators** stay on AppDelegate for now. They access moved dependencies through the forwarding properties. No changes needed for these until a future migration.

### Backward Compatibility

Many call sites across the codebase use `Application.appDelegate.xxx` or `NSApp.delegateTyped.xxx`. These continue working via forwarding computed properties on AppDelegate. Call site migration is out of scope — forwarding properties are removed incrementally in future work.

### Initializing State Changes

`Initializing` gains responsibility for crash handler setup:

```swift
@MainActor
struct Initializing: InitializingHandling {

    init() {}

    mutating func handleWillFinishLaunching() {
        // Crash handler setup (from AppDelegate lines 434-442)
        let didCrashDuringCrashHandlersSetUp = UserDefaultsWrapper(key: .didCrashDuringCrashHandlersSetUp, defaultValue: false)
        if case .normal = AppVersion.runType,
           !didCrashDuringCrashHandlersSetUp.wrappedValue {
            didCrashDuringCrashHandlersSetUp.wrappedValue = true
            CrashLogMessageExtractor.setUp(swapCxaThrow: false)
            didCrashDuringCrashHandlersSetUp.wrappedValue = false
        }

        // PixelKit configuration
        if AppVersion.runType.requiresEnvironment {
            AppDelegate.configurePixelKit()
        }
    }

    func makeLaunchingState() throws -> any LaunchingHandling {
        return try Launching()
    }

}
```

### Post-super.init() Properties

Several current AppDelegate properties are initialized after `super.init()` because they capture `self`:

- `memoryPressureReporter`, `memoryUsageIntervalReporter` — capture `self` for reporting callbacks
- `autoClearHandler` — set during `applicationDidFinishLaunching`
- `stateRestorationManager` — set during `applicationWillFinishLaunching`
- `appIconChanger` — set during `applicationWillFinishLaunching`

Since `Launching` is a class, it can use two-phase initialization: assign stored properties first, then set up self-referencing closures and subscriptions (including Combine cancellables like `isInternalUserSharingCancellable`, `isSyncInProgressCancellable`, etc.) in the same `init()`.

Properties that are currently set during lifecycle callbacks (`stateRestorationManager`, `autoClearHandler`, `appIconChanger`) move into `Launching.init()` since their creation doesn't truly depend on the lifecycle timing — they were in lifecycle callbacks as a side effect of AppDelegate's structure.

### Startup Profiler

`startupProfiler` moves to `AppDependencies`. The profiler measurement currently wrapping `AppDelegate.init()` will wrap `Launching.init()` instead, and the `appWillFinishLaunching` measurement stays with `Initializing.handleWillFinishLaunching()`.

### Test and Debug Code Paths

`AppDelegate.init()` has conditional logic for `.unitTests`, `.integrationTests`, `.xcPreviews` run types (mock key stores, mock feature flaggers, nil database). `Launching.init()` preserves these branches. The state machine tests continue using `MockLaunching` at the protocol level, so they are unaffected.

## Migration Strategy

The migration is incremental, not big-bang:

1. Create `AppDependencies` struct with sub-container types (empty initially). Finalize property-to-container groupings.
2. Change `Launching` from struct to class. Change `Initializing` to remove AppDelegate reference.
3. Move properties from `AppDelegate.init()` to `Launching.init()` in batches, grouped by sub-container. Order: Stores → FeatureFlags → Preferences → Services → UI → Subscription. For each batch:
   a. Move properties to `Launching`, add to relevant sub-container
   b. Add forwarding computed properties on AppDelegate
   c. Verify build
4. Update `Foreground` to hold `AppDependencies` instead of `weak var appDelegate`. Update termination deciders to use `AppDependencies` fields.
5. Update `Initializing` to handle crash setup and remove AppDelegate dependency.

**Ordering constraint:** The init chain has dependencies (database before keyValueStore before featureFlagger, etc.). `Launching.init()` must respect this ordering. The batched approach follows the same natural dependency order.

**Foreground transition:** During batched migration (step 3), `Foreground` still holds `weak var appDelegate` and accesses properties through forwarding computed properties. In step 4, `Foreground` switches to `AppDependencies` and the forwarding properties remain only for external call sites.

## Testing

- **State machine tests:** Existing 19 tests continue passing. `MockLaunching` and `MockForeground` are unchanged at the protocol level.
- **Launching tests:** Verify `AppDependencies` is created and `makeForegroundState()` returns a configured `Foreground`. Given `Launching` creates real dependencies, these are closer to integration tests.
- **Forwarding properties:** No dedicated tests — trivial pass-throughs.
- **Test code paths:** `Launching.init()` preserves existing `.unitTests`/`.integrationTests`/`.xcPreviews` branching from `AppDelegate.init()`.
- **Testability:** No protocol-based injection for `Launching` in this sub-project (YAGNI). Can be added later if needed.

## Out of Scope

- Migrating `applicationDidFinishLaunching` logic (Sub-project 3)
- Migrating `applicationDidBecomeActive` logic (Sub-project 4)
- Migrating `applicationWillFinishLaunching` logic beyond crash handlers (Sub-project 2)
- Removing forwarding properties / updating call sites across the codebase
- `lazy var` UI coordinators migration (these stay on AppDelegate, accessing moved dependencies through forwarding properties)
