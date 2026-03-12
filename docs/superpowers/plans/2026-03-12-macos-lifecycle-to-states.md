# macOS Lifecycle Methods → State Machine Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all setup logic from `applicationWillFinishLaunching` and `applicationDidFinishLaunching` into state machine handlers, making AppDelegate lifecycle callbacks thin dispatchers.

**Architecture:** Add a new `.appDidFinishLaunching` event to the state machine. Repurpose `.willFinishLaunching` for Launching (not Initializing). Move `applicationWillFinishLaunching` code into `Launching.handleWillFinishLaunching()` and `applicationDidFinishLaunching` code into `Foreground.onTransition()`.

**Tech Stack:** Swift, AppKit, Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-03-12-macos-lifecycle-to-states-design.md`

---

## Chunk 1: State Machine Protocol & Event Changes (with tests)

### Task 1: Update state machine events, protocols, and transition logic

This task changes the state machine core: adds the new `.appDidFinishLaunching` event, updates protocols, and rewires transitions. Tests are updated alongside the production code since mock types must match protocol changes.

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStateMachine.swift`
- Modify: `macOS/UnitTests/AppLifecycle/AppStateMachineTests.swift`

- [ ] **Step 1: Add `.appDidFinishLaunching` event and update `LaunchingHandling` protocol**

In `AppStateMachine.swift`:

1. Add new event case:
```swift
enum AppEvent {
    case willFinishLaunching
    case didFinishLaunching
    case appDidFinishLaunching  // NEW: triggers Launching → Foreground
    case didBecomeActive
}
```

2. Remove `handleWillFinishLaunching()` from `InitializingHandling`:
```swift
@MainActor
protocol InitializingHandling {
    init()
    func makeLaunchingState() throws -> any LaunchingHandling
}
```

3. Add `handleWillFinishLaunching()` to `LaunchingHandling`:
```swift
@MainActor
protocol LaunchingHandling {
    func handleWillFinishLaunching()
    func makeForegroundState() throws -> any ForegroundHandling
}
```

4. Update `respond(to:in: initializing)` — remove `.willFinishLaunching` handling:
```swift
private func respond(to event: AppEvent, in initializing: inout any InitializingHandling) {
    switch event {
    case .didFinishLaunching:
        do {
            currentState = try .launching(initializing.makeLaunchingState())
        } catch {
            let terminating = terminatingStateFactory.makeTerminatingState(error: error)
            terminating.terminate()
            currentState = .terminating(terminating)
        }
    default:
        handleUnexpectedEvent(event)
    }
}
```

Note: the `initializing` parameter is no longer `inout` since we don't mutate it. Change the signature to:
```swift
private func respond(to event: AppEvent, in initializing: any InitializingHandling) {
```
And update the call site in `handle(_:)`:
```swift
case .initializing(let initializing):
    respond(to: event, in: initializing)
```

5. Update `respond(to:in: launching)` — handle `.willFinishLaunching` and `.appDidFinishLaunching`:
```swift
private func respond(to event: AppEvent, in launching: any LaunchingHandling) {
    switch event {
    case .willFinishLaunching:
        launching.handleWillFinishLaunching()
    case .appDidFinishLaunching:
        do {
            let foreground = try launching.makeForegroundState()
            foreground.onTransition()
            currentState = .foreground(foreground)
        } catch {
            let terminating = terminatingStateFactory.makeTerminatingState(error: error)
            terminating.terminate()
            currentState = .terminating(terminating)
        }
    default:
        handleUnexpectedEvent(event)
    }
}
```

- [ ] **Step 2: Update mock types in tests**

In `AppStateMachineTests.swift`:

1. Update `MockInitializing` — remove `handleWillFinishLaunching`:
```swift
@MainActor
final class MockInitializing: InitializingHandling {

    var shouldThrowOnLaunching = false

    init() {}

    func makeLaunchingState() throws -> any LaunchingHandling {
        if shouldThrowOnLaunching {
            throw NSError(domain: "test", code: 1)
        }
        return MockLaunching()
    }

}
```

2. Update `MockLaunching` — add `handleWillFinishLaunching`:
```swift
@MainActor
final class MockLaunching: LaunchingHandling {

    var shouldThrowOnForeground = false
    private(set) var willFinishLaunchingCalled = false

    func handleWillFinishLaunching() {
        willFinishLaunchingCalled = true
    }

    func makeForegroundState() throws -> any ForegroundHandling {
        if shouldThrowOnForeground {
            throw NSError(domain: "test", code: 2)
        }
        return MockForeground()
    }

}
```

- [ ] **Step 3: Update existing tests for new event flow**

In `AppStateMachineTests.swift`:

1. **InitializingTests** — remove `willFinishLaunching()` test, update `didBecomeActiveIgnored`:

Remove the entire `willFinishLaunching()` test method.

Add test for `.willFinishLaunching` being ignored in initializing:
```swift
@Test("willFinishLaunching in initializing should be ignored")
func willFinishLaunchingIgnored() {
    stateMachine.handle(.willFinishLaunching)
    #expect(stateMachine.currentState.name == "initializing")
}
```

Add test for `.appDidFinishLaunching` being ignored in initializing:
```swift
@Test("appDidFinishLaunching in initializing should be ignored")
func appDidFinishLaunchingIgnored() {
    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "initializing")
}
```

2. **LaunchingTests** — change transition trigger from `.didBecomeActive` to `.appDidFinishLaunching`:

Update `transitionToForeground()`:
```swift
@Test("appDidFinishLaunching should transition from launching to foreground and call onTransition")
func transitionToForeground() {
    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "foreground")

    if case .foreground(let foreground) = stateMachine.currentState,
       let mock = foreground as? MockForeground {
        #expect(mock.eventLog == ["onTransition"])
    } else {
        Issue.record("Expected foreground state with MockForeground")
    }
}
```

Update `transitionToTerminatingOnError()`:
```swift
@Test("appDidFinishLaunching with error should transition to terminating")
func transitionToTerminatingOnError() {
    if case .launching(let launching) = stateMachine.currentState,
       let mock = launching as? MockLaunching {
        mock.shouldThrowOnForeground = true
    }
    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "terminating")
}
```

Replace `willFinishLaunchingIgnored()` with a test that `.willFinishLaunching` IS handled (calls handleWillFinishLaunching but stays in launching):
```swift
@Test("willFinishLaunching in launching should call handleWillFinishLaunching and stay in launching")
func willFinishLaunchingHandled() {
    stateMachine.handle(.willFinishLaunching)
    #expect(stateMachine.currentState.name == "launching")

    if case .launching(let launching) = stateMachine.currentState,
       let mock = launching as? MockLaunching {
        #expect(mock.willFinishLaunchingCalled)
    } else {
        Issue.record("Expected launching state with MockLaunching")
    }
}
```

Replace `didFinishLaunchingIgnored` — now `.didBecomeActive` should also be ignored in launching:
```swift
@Test("didFinishLaunching in launching should be ignored")
func didFinishLaunchingIgnored() {
    stateMachine.handle(.didFinishLaunching)
    #expect(stateMachine.currentState.name == "launching")
}

@Test("didBecomeActive in launching should be ignored")
func didBecomeActiveIgnored() {
    stateMachine.handle(.didBecomeActive)
    #expect(stateMachine.currentState.name == "launching")
}
```

3. **ForegroundTests** — add test for `.appDidFinishLaunching` being ignored:
```swift
@Test("appDidFinishLaunching in foreground should be ignored")
func appDidFinishLaunchingIgnored() {
    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "foreground")
}
```

4. **TerminatingTests** — add `.appDidFinishLaunching` to `allEventsIgnored()`:
```swift
@Test("All events in terminating should be ignored")
func allEventsIgnored() {
    stateMachine.handle(.willFinishLaunching)
    #expect(stateMachine.currentState.name == "terminating")

    stateMachine.handle(.didFinishLaunching)
    #expect(stateMachine.currentState.name == "terminating")

    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "terminating")

    stateMachine.handle(.didBecomeActive)
    #expect(stateMachine.currentState.name == "terminating")
}
```

5. **FullLifecycleTests** — update `fullLifecycle()`:
```swift
@Test("Full lifecycle: initializing → launching → foreground → terminating")
func fullLifecycle() {
    let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()), terminatingStateFactory: MockTerminatingStateFactory())

    stateMachine.handle(.didFinishLaunching)
    #expect(stateMachine.currentState.name == "launching")

    stateMachine.handle(.willFinishLaunching)
    #expect(stateMachine.currentState.name == "launching")

    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "foreground")

    let reply = stateMachine.handleTerminationRequest()
    #expect(reply == .terminateNow)
    #expect(stateMachine.currentState.name == "terminating")
}
```

Update `earlyDidBecomeActiveIgnored()` — `.willFinishLaunching` is no longer relevant for Initializing, and `.didBecomeActive` is ignored in launching:
```swift
@Test("didBecomeActive before appDidFinishLaunching is ignored in launching")
func earlyDidBecomeActiveIgnored() {
    let stateMachine = AppStateMachine(initialState: .launching(MockLaunching()), terminatingStateFactory: MockTerminatingStateFactory())

    stateMachine.handle(.didBecomeActive)
    #expect(stateMachine.currentState.name == "launching")

    stateMachine.handle(.appDidFinishLaunching)
    #expect(stateMachine.currentState.name == "foreground")
}
```

- [ ] **Step 4: Build and run tests**

Build with Xcode MCP (`BuildProject`), then run tests via Xcode MCP (`RunSomeTests`) for all test suites in `AppStateMachineTests.swift`: `InitializingTests`, `LaunchingTests`, `ForegroundTests`, `TerminatingTests`, `FullLifecycleTests`.

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStateMachine.swift macOS/UnitTests/AppLifecycle/AppStateMachineTests.swift
git commit -m "refactor: add .appDidFinishLaunching event, move willFinishLaunching to LaunchingHandling"
```

---

### Task 2: Update Initializing to move crash handler setup into init()

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Initializing.swift`

- [ ] **Step 1: Move crash handler + PixelKit setup from handleWillFinishLaunching() to init()**

Replace the entire file content:

```swift
@MainActor
struct Initializing: InitializingHandling {

    init() {
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

Keep the existing license header and imports (`Common`, `Crashes`, `Foundation`, `PixelKit`).

- [ ] **Step 2: Build**

Build with Xcode MCP. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Initializing.swift
git commit -m "refactor: move crash handler and PixelKit setup into Initializing.init()"
```

---

### Task 3: Update AppDelegate.init() to only dispatch .didFinishLaunching

Currently `AppDelegate.init()` dispatches both `.willFinishLaunching` and `.didFinishLaunching`. Now it should dispatch only `.didFinishLaunching` since crash handler setup moved to `Initializing.init()` and `.willFinishLaunching` is now for Launching.

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

- [ ] **Step 1: Remove .willFinishLaunching dispatch from init()**

In `AppDelegate.swift` around line 299-301, the current code is:
```swift
appStateMachine = AppStateMachine(initialState: .initializing(Initializing()))
appStateMachine.handle(.willFinishLaunching)
appStateMachine.handle(.didFinishLaunching)
```

Remove the `.willFinishLaunching` line:
```swift
appStateMachine = AppStateMachine(initialState: .initializing(Initializing()))
appStateMachine.handle(.didFinishLaunching)
```

- [ ] **Step 2: Build**

Build with Xcode MCP. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "refactor: only dispatch .didFinishLaunching in AppDelegate.init()"
```

---

## Chunk 2: Move applicationWillFinishLaunching code into Launching

### Task 4: Add handleWillFinishLaunching() to Launching and move code from AppDelegate

This task moves the ~50 lines from `AppDelegate.applicationWillFinishLaunching` into `Launching.handleWillFinishLaunching()`. The Launching class already has `dependencies` with all the necessary properties.

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift`
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

- [ ] **Step 1: Add handleWillFinishLaunching() to Launching**

In `Launching.swift`, add after `init()` closes (around line 1031):

```swift
func handleWillFinishLaunching() {
    let profilerToken = dependencies.services.startupProfiler.startMeasuring(.appWillFinishLaunching)
    defer {
        profilerToken.stop()
    }

    do {
        try DefaultReinstallUserDetection(keyValueStore: dependencies.stores.keyValueStore).checkForReinstallingUser()
    } catch {
        Logger.general.error("Problem when checking for reinstalling user: \(error.localizedDescription)")
    }

    APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent())

    dependencies.services.stateRestorationManager = AppStateRestorationManager(
        fileStore: dependencies.stores.fileStore,
        startupPreferences: dependencies.preferences.startupPreferences,
        tabsPreferences: dependencies.preferences.tabsPreferences,
        keyValueStore: dependencies.stores.keyValueStore,
        sessionRestorePromptCoordinator: SessionRestorePromptCoordinator(pixelFiring: PixelKit.shared),
        pixelFiring: PixelKit.shared
    )

    initializeUpdateController()

    dependencies.services.appIconChanger = AppIconChanger(
        internalUserDecider: dependencies.featureFlags.internalUserDecider,
        appearancePreferences: dependencies.preferences.appearancePreferences
    )

    if AppVersion.runType.requiresEnvironment {
        let vpnUninstaller = VPNUninstaller(
            pinningManager: dependencies.ui.pinningManager,
            ipcClient: VPNControllerXPCClient.shared
        )
        let featureGatekeeper = DefaultVPNFeatureGatekeeper(
            vpnUninstaller: vpnUninstaller,
            subscriptionManager: dependencies.subscription.subscriptionManager
        )
        let tunnelController = NetworkProtectionIPCTunnelController(
            featureGatekeeper: featureGatekeeper,
            ipcClient: VPNControllerXPCClient.shared
        )

        vpnSubscriptionEventHandler = VPNSubscriptionEventsHandler(
            subscriptionManager: dependencies.subscription.subscriptionManager,
            tunnelController: tunnelController,
            vpnUninstaller: vpnUninstaller
        )

        dependencies.services.freemiumDBPFeature.subscribeToDependencyUpdates()
    }

    // macOS UI framework workarounds
    _ = NSPopover.swizzleShowRelativeToRectOnce
    NSWindow.allowsAutomaticWindowTabbing = false
    SwiftUIContextMenuRetainCycleFix.setUp()
}
```

Also add the `vpnSubscriptionEventHandler` stored property on Launching (near the other non-AppDependencies properties, around line 85):
```swift
private(set) var vpnSubscriptionEventHandler: VPNSubscriptionEventsHandler?
```

Also move `initializeUpdateController()` from AppDelegate to Launching. Read the method from AppDelegate (around line 744-788) and add it as a private method on Launching, adapting property references to use `dependencies.xxx` paths. The method creates either an AppStore or Sparkle update controller based on build type.

- [ ] **Step 2: Replace AppDelegate.applicationWillFinishLaunching with state machine dispatch**

In `AppDelegate.swift`, replace the body of `applicationWillFinishLaunching(_:)` with:
```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    appStateMachine.handle(.willFinishLaunching)
}
```

Remove `initializeUpdateController()` from AppDelegate (it moved to Launching).

- [ ] **Step 3: Build**

Build with Xcode MCP. Expected: success. If there are compile errors from missing references, fix them — some lazy properties on AppDelegate that reference `stateRestorationManager` or `updateController` may need adjustment since those are now set during `handleWillFinishLaunching()` rather than in the AppDelegate method body.

- [ ] **Step 4: Run state machine tests**

Run all test suites via Xcode MCP. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift macOS/DuckDuckGo/Application/AppDelegate.swift
git commit -m "refactor: move applicationWillFinishLaunching code into Launching.handleWillFinishLaunching()"
```

---

## Chunk 3: Move applicationDidFinishLaunching code into Foreground.onTransition()

### Task 5: Move applicationDidFinishLaunching code into Foreground.onTransition()

This is the largest task — ~140 lines of setup code plus ~12 private helper methods move from AppDelegate to Foreground. The Foreground class already holds `dependencies: AppDependencies`.

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Foreground.swift`
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift`

- [ ] **Step 1: Add stored properties to Foreground**

These properties are currently on AppDelegate and will be set during `onTransition()`. Add them as stored properties on `Foreground`:

```swift
// Properties set during onTransition
private var vpnSubscriptionEventHandler: VPNSubscriptionEventsHandler?
private var freemiumDBPScanResultPolling: FreemiumDBPScanResultPolling?
private(set) var aiChatSyncCleaner: AIChatSyncCleaning?
private(set) var autofillPixelReporter: AutofillPixelReporter?
private var passwordsStatusBarMenu: PasswordsStatusBarMenu?
private var passwordsMenuBarCancellable: AnyCancellable?
private var isInternalUserSharingCancellable: AnyCancellable?
private var isSyncInProgressCancellable: AnyCancellable?
private var syncFeatureFlagsCancellable: AnyCancellable?
private var screenLockedCancellable: AnyCancellable?
private var emailCancellables = Set<AnyCancellable>()
private var updateProgressCancellable: AnyCancellable?
private(set) var webExtensionManager: WebExtensionManaging?
private var webExtensionFeatureFlagHandler: AnyObject?
private var isSyncingEmbeddedExtensions = false
private(set) var darkReaderFeatureSettings: DarkReaderFeatureSettings?
private var darkReaderCancellables = Set<AnyCancellable>()
private var automationServer: AutomationServer?
@UserDefaultsWrapper(key: .syncDidShowSyncPausedByFeatureFlagAlert, defaultValue: false)
private var syncDidShowSyncPausedByFeatureFlagAlert: Bool
```

**Imports to add to Foreground.swift:** `Combine`, `Common`, `os.log`, `DDGSync`, `Subscription`, `NetworkProtection`, `NetworkProtectionIPC`, `WebExtensions`, `Lottie`, `Freemium`, `DataBrokerProtection_macOS`, `History`, `Bookmarks`, `Configuration`, `Networking`, `FeatureFlags`, `BWManagementShared`, `UserNotifications`, `SyncDataProviders`, `Persistence`, and any others required by the moved code. Fix missing imports iteratively during the build step.

Update `Foreground.init()` to also accept `vpnSubscriptionEventHandler`:
```swift
init(dependencies: AppDependencies, vpnSubscriptionEventHandler: VPNSubscriptionEventsHandler? = nil) {
    self.dependencies = dependencies
    self.vpnSubscriptionEventHandler = vpnSubscriptionEventHandler
}
```

Update `Launching.makeForegroundState()` to pass it:
```swift
func makeForegroundState() throws -> any ForegroundHandling {
    Foreground(dependencies: dependencies, vpnSubscriptionEventHandler: vpnSubscriptionEventHandler)
}
```

- [ ] **Step 2: Implement onTransition() with the applicationDidFinishLaunching code**

Move the entire body of `AppDelegate.applicationDidFinishLaunching` (lines 510-648) into `Foreground.onTransition()`, adapting all property references from forwarding properties to `dependencies.xxx` paths.

Key adaptations:
- `startupProfiler` → `dependencies.services.startupProfiler`
- `subscriptionManager` → `dependencies.subscription.subscriptionManager`
- `historyCoordinator` → `dependencies.services.historyCoordinator`
- `privacyFeatures` → `dependencies.services.privacyFeatures`
- `bookmarkManager` → `dependencies.services.bookmarkManager`
- `configurationManager` → `dependencies.services.configurationManager`
- `keyValueStore` → `dependencies.stores.keyValueStore`
- `featureFlagger` → `dependencies.featureFlags.featureFlagger`
- `windowControllersManager` → `dependencies.ui.windowControllersManager`
- `startupPreferences` → `dependencies.preferences.startupPreferences`
- `dataClearingPreferences` → `dependencies.preferences.dataClearingPreferences`
- `appearancePreferences` → `dependencies.preferences.appearancePreferences`
- `pinningManager` → `dependencies.ui.pinningManager`
- etc.

Items that stay on AppDelegate (handled in Step 3):
- `didFinishLaunching = true` — stays on AppDelegate
- `UNUserNotificationCenter.current().delegate = self` — stays on AppDelegate

Lazy properties referenced (like `vpnAppEventsHandler`, `vpnUpsellVisibilityManager`, `dataBrokerProtectionSubscriptionEventHandler`, `wideEventService`): create them locally in `onTransition()` or as lazy properties on Foreground.

- [ ] **Step 3: Move private helper methods from AppDelegate to Foreground**

Move these methods from AppDelegate to Foreground, adapting property references:
- `setupWebExtensions()` (and `initializeWebExtensions()`, `syncEmbeddedExtensions()` if they are separate)
- `startupSync()` (and `subscribeToSyncFeatureFlags()`, `subscribeSyncQueueToScreenLockedNotifications()`)
- `setUpAutoClearHandler()`
- `setUpAutofillPixelReporter()`
- `setUpPasswordsMenuBarVisibility()`
- `subscribeToEmailProtectionStatusNotifications()` (and the handler methods: `emailDidSignInNotification`, `emailDidSignOutNotification`)
- `subscribeToDataImportCompleteNotification()` (and the handler method: `dataImportCompleteNotification`)
- `subscribeToInternalUserChanges()`
- `subscribeToUpdateControllerChanges()`
- `startAutomationServerIfNeeded()`
- `applyPreferredTheme()`
- `fireFailedCompilationsPixelIfNeeded()`

Remove these methods from AppDelegate after moving them.

- [ ] **Step 4: Replace AppDelegate.applicationDidFinishLaunching with thin dispatcher**

In `AppDelegate.swift`, replace the body of `applicationDidFinishLaunching(_:)` with:
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    appStateMachine.handle(.appDidFinishLaunching)
    guard AppVersion.runType.requiresEnvironment else { return }
    didFinishLaunching = true
    UNUserNotificationCenter.current().delegate = self
}
```

Note: The `guard` preserves the current behavior where `didFinishLaunching` is not set in test/preview environments.

Also remove the stored properties from AppDelegate that moved to Foreground:
- `automationServer`
- `vpnSubscriptionEventHandler`
- `freemiumDBPScanResultPolling`
- `aiChatSyncCleaner`
- `autofillPixelReporter`
- `passwordsStatusBarMenu`
- `passwordsMenuBarCancellable`
- `isInternalUserSharingCancellable`
- `isSyncInProgressCancellable`
- `syncFeatureFlagsCancellable`
- `screenLockedCancellable`
- `emailCancellables`
- `updateProgressCancellable`
- `webExtensionManager`, `webExtensionFeatureFlagHandler`, `darkReaderFeatureSettings`, `darkReaderCancellables`
- `isSyncingEmbeddedExtensions`

Also remove lazy properties that moved:
- `dataBrokerProtectionSubscriptionEventHandler`
- `wideEventService`
- `sessionRestorePromptCoordinator` (if it moved to Launching)

**Keep on AppDelegate:** `vpnAppEventsHandler` — it's still used in `applicationDidBecomeActive` (line ~693). In `Foreground.onTransition()`, call `Application.appDelegate.vpnAppEventsHandler.applicationDidFinishLaunching()` for the didFinishLaunching call, or create a separate local instance.

**Important:** Keep lazy properties that are still used by other AppDelegate methods or by external call sites through forwarding properties. Only remove properties that are exclusively used in the moved code.

- [ ] **Step 5: Build**

Build with Xcode MCP. This is the most likely step to have compile errors — expect issues from:
- Missing imports in Foreground.swift (add needed imports)
- Forwarding properties on AppDelegate that reference removed properties
- Lazy properties that reference moved properties

Fix all compile errors iteratively.

- [ ] **Step 6: Run all state machine and termination tests**

Run all test suites via Xcode MCP: `InitializingTests`, `LaunchingTests`, `ForegroundTests`, `TerminatingTests`, `FullLifecycleTests`, `TerminationDeciderHandlerTests`.

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Foreground.swift macOS/DuckDuckGo/Application/AppDelegate.swift macOS/DuckDuckGo/Application/AppLifecycle/AppStates/Launching.swift
git commit -m "refactor: move applicationDidFinishLaunching code into Foreground.onTransition()"
```

---

## Chunk 4: Wire up AppDelegate.applicationDidBecomeActive and verify

### Task 6: Update applicationDidBecomeActive to use new event flow

Currently `applicationDidBecomeActive` dispatches `.didBecomeActive` which used to trigger Launching → Foreground. Now it should stay as-is (the dispatch still happens, but it calls `didReturn()` on Foreground instead). Verify the existing logic still works.

**Files:**
- Modify: `macOS/DuckDuckGo/Application/AppDelegate.swift` (if needed)

- [ ] **Step 1: Verify applicationDidBecomeActive still works**

The current code at `AppDelegate.applicationDidBecomeActive` (line ~664) already has:
```swift
guard didFinishLaunching else { return }
appStateMachine.handle(.didBecomeActive)
```

This should continue working — `.didBecomeActive` in Foreground calls `didReturn()` (a no-op). The rest of the method body stays on AppDelegate as-is. No changes needed unless the build revealed issues.

- [ ] **Step 2: Full build and test**

Build with Xcode MCP. Run all state machine tests + termination decider tests.

Expected: All pass.

- [ ] **Step 3: Commit (if any changes were needed)**

Only commit if changes were made in Step 1.

---

### Task 7: Smoke test and final verification

- [ ] **Step 1: Run the app**

Launch the macOS app from Xcode. Verify:
- App launches without crash
- Window opens correctly
- Basic browsing works (navigate to a URL)
- Quit works (Cmd+Q)

- [ ] **Step 2: Run full state machine + termination test suite**

Run all tests via Xcode MCP one final time.

- [ ] **Step 3: Push to remote**

```bash
git push origin dominik/macos-lifecycle-methods
```
