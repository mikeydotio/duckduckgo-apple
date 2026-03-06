# Autoplay Exceptions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-domain autoplay exceptions so users can override the global autoplay blocking mode for specific sites.

**Architecture:** Extend `AutoplayPreferences` with an `exceptions: [String: AutoplayBlockingMode]` dictionary and an `effectiveMode(for:)` resolver. A new `AutoplayTabExtension` (NavigationResponder) applies the effective mode to the WebView's `mediaTypesRequiringUserActionForPlayback` on each navigation start, reloading if the mode changed. A SwiftUI sheet wired into the General Settings Permissions section lets users manage per-domain overrides.

**Tech Stack:** Swift, Combine, SwiftUI, `WKWebViewConfiguration`, `UserDefaultsWrapper`, `NavigationResponder` / `TabExtension` protocols.

---

## Task 1: Data model — exceptions storage + `effectiveMode(for:)`

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift:56`
- Modify: `macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift`
- Modify: `macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift`

### Step 1: Add UserDefaults key

In `UserDefaultsWrapper.swift`, add the new key immediately after line 56 (`case autoplayBlockingMode`):

```swift
case autoplayExceptions = "preferences.autoplay.exceptions"
```

### Step 2: Write failing tests

In `AutoplayPreferencesTests.swift`, add a new section after the existing tests. Start with a mock that supports exceptions:

```swift
final class AutoplayPreferencesPersistorMockV2: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
    var autoplayExceptionsRawValue: [String: String]
    init(mode: String = AutoplayBlockingMode.blockAudio.rawValue,
         exceptions: [String: String] = [:]) {
        self.autoplayBlockingModeRawValue = mode
        self.autoplayExceptionsRawValue = exceptions
    }
}
```

Then add a new `AutoplayExceptionsTests` class in the same file:

```swift
final class AutoplayExceptionsTests: XCTestCase {

    // MARK: - effectiveMode(for:) resolution

    func testEffectiveModeReturnsExceptionWhenDomainMatches() {
        let persistor = AutoplayPreferencesPersistorMockV2(
            mode: AutoplayBlockingMode.blockAudio.rawValue,
            exceptions: ["youtube.com": "allowAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .allowAll)
    }

    func testEffectiveModeFallsBackToGlobalWhenNoDomainMatch() {
        let persistor = AutoplayPreferencesPersistorMockV2(
            mode: AutoplayBlockingMode.blockAll.rawValue,
            exceptions: ["otherdomain.com": "allowAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .blockAll)
    }

    func testEffectiveModeStripsWWWPrefix() {
        let persistor = AutoplayPreferencesPersistorMockV2(
            mode: AutoplayBlockingMode.blockAudio.rawValue,
            exceptions: ["youtube.com": "blockAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .blockAll)
    }

    func testEffectiveModeForNilHostFallsBackToGlobal() {
        let persistor = AutoplayPreferencesPersistorMockV2(
            mode: AutoplayBlockingMode.allowAll.rawValue
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "about:blank")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .allowAll)
    }

    // MARK: - exceptions persistence

    func testAddExceptionPersistsToStorage() {
        let persistor = AutoplayPreferencesPersistorMockV2()
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.exceptions["youtube.com"] = .allowAll

        XCTAssertEqual(persistor.autoplayExceptionsRawValue, ["youtube.com": "allowAll"])
    }

    func testRemoveExceptionPersistsToStorage() {
        let persistor = AutoplayPreferencesPersistorMockV2(exceptions: ["youtube.com": "allowAll"])
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.exceptions.removeValue(forKey: "youtube.com")

        XCTAssertTrue(persistor.autoplayExceptionsRawValue.isEmpty)
    }

    func testExceptionsLoadedFromStorageOnInit() {
        let persistor = AutoplayPreferencesPersistorMockV2(exceptions: ["youtube.com": "blockAll"])
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.exceptions["youtube.com"], .blockAll)
    }

    func testInvalidExceptionRawValueIsIgnoredOnLoad() {
        let persistor = AutoplayPreferencesPersistorMockV2(exceptions: ["youtube.com": "bogusValue"])
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertNil(prefs.exceptions["youtube.com"])
    }

    func testExceptionsObjectWillChangeFires() {
        let persistor = AutoplayPreferencesPersistorMockV2()
        let prefs = AutoplayPreferences(persistor: persistor)

        let exp = expectation(description: "objectWillChange")
        let cancellable = prefs.objectWillChange.sink { exp.fulfill() }

        prefs.exceptions["youtube.com"] = .allowAll
        waitForExpectations(timeout: 0)
        withExtendedLifetime(cancellable) {}
    }
}
```

### Step 3: Run tests to confirm they fail

```bash
xcodebuild test \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "macOS Unit Tests" \
  -only-testing "Unit Tests/AutoplayExceptionsTests" \
  2>&1 | tail -30
```

Expected: **FAIL** — compiler error: `AutoplayPreferencesPersistor` has no member `autoplayExceptionsRawValue`, `AutoplayPreferences` has no `exceptions` or `effectiveMode`.

### Step 4: Extend `AutoplayPreferencesPersistor` and `AutoplayPreferences`

In `AutoplayPreferences.swift`, make these changes:

**a) Add to `AutoplayPreferencesPersistor` protocol:**

```swift
protocol AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String { get set }
    var autoplayExceptionsRawValue: [String: String] { get set }
}
```

**b) Extend `AutoplayPreferencesUserDefaultsPersistor`:**

```swift
struct AutoplayPreferencesUserDefaultsPersistor: AutoplayPreferencesPersistor {
    @UserDefaultsWrapper(key: .autoplayBlockingMode, defaultValue: AutoplayBlockingMode.blockAudio.rawValue)
    var autoplayBlockingModeRawValue: String

    @UserDefaultsWrapper(key: .autoplayExceptions, defaultValue: [:])
    var autoplayExceptionsRawValue: [String: String]
}
```

**c) Add `exceptions` to `AutoplayPreferences`:**

```swift
@Published var exceptions: [String: AutoplayBlockingMode] {
    didSet {
        persistor.autoplayExceptionsRawValue = exceptions.reduce(into: [:]) { $0[$1.key] = $1.value.rawValue }
    }
}
```

**d) Update `init` to load exceptions:**

```swift
init(persistor: AutoplayPreferencesPersistor = AutoplayPreferencesUserDefaultsPersistor()) {
    self.persistor = persistor
    self.autoplayBlockingMode = AutoplayBlockingMode(rawValue: persistor.autoplayBlockingModeRawValue) ?? .blockAudio
    self.exceptions = persistor.autoplayExceptionsRawValue.reduce(into: [:]) {
        if let mode = AutoplayBlockingMode(rawValue: $1.value) {
            $0[$1.key] = mode
        }
    }
}
```

**e) Add `effectiveMode(for:)` helper:**

```swift
func effectiveMode(for url: URL) -> AutoplayBlockingMode {
    guard let host = url.host else { return autoplayBlockingMode }
    let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    return exceptions[domain] ?? autoplayBlockingMode
}
```

**f) Update the existing mock** in `AutoplayPreferencesTests.swift` — `AutoplayPreferencesPersistorMock` now needs `autoplayExceptionsRawValue`:

```swift
final class AutoplayPreferencesPersistorMock: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
    var autoplayExceptionsRawValue: [String: String] = [:]
    init(autoplayBlockingModeRawValue: String) {
        self.autoplayBlockingModeRawValue = autoplayBlockingModeRawValue
    }
}
```

Remove `AutoplayPreferencesPersistorMockV2` from the test file — both existing tests and new tests can share the same mock now. Update `AutoplayExceptionsTests` to use `AutoplayPreferencesPersistorMock` with an initializer that accepts exceptions:

```swift
// Update AutoplayPreferencesPersistorMock to support exceptions in init:
final class AutoplayPreferencesPersistorMock: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
    var autoplayExceptionsRawValue: [String: String]
    init(autoplayBlockingModeRawValue: String = AutoplayBlockingMode.blockAudio.rawValue,
         autoplayExceptionsRawValue: [String: String] = [:]) {
        self.autoplayBlockingModeRawValue = autoplayBlockingModeRawValue
        self.autoplayExceptionsRawValue = autoplayExceptionsRawValue
    }
}
```

Update the existing tests that use the old `AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue:)` pattern — they still compile because the new `init` has a default for `autoplayExceptionsRawValue`.

### Step 5: Run tests to verify they pass

```bash
xcodebuild test \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "macOS Unit Tests" \
  -only-testing "Unit Tests/AutoplayPreferencesTests" \
  -only-testing "Unit Tests/AutoplayExceptionsTests" \
  2>&1 | tail -30
```

Expected: all tests **PASS**.

### Step 6: Commit

```bash
git add macOS/DuckDuckGo/Common/Utilities/UserDefaultsWrapper.swift \
        macOS/DuckDuckGo/Preferences/Model/AutoplayPreferences.swift \
        macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift
git commit -m "feat: add autoplay exceptions data model and effectiveMode(for:)"
```

---

## Task 2: `AutoplayTabExtension` (TDD)

**Files:**
- Create: `macOS/UnitTests/Autoplay/AutoplayTabExtensionTests.swift`
- Create: `macOS/DuckDuckGo/Tab/TabExtensions/AutoplayTabExtension.swift`

### Step 1: Write failing tests

Create `macOS/UnitTests/Autoplay/AutoplayTabExtensionTests.swift`:

```swift
//
//  AutoplayTabExtensionTests.swift
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

import Combine
import Navigation
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AutoplayTabExtensionTests: XCTestCase {

    // MARK: - Helpers

    private func makePreferences(
        globalMode: AutoplayBlockingMode = .blockAudio,
        exceptions: [String: AutoplayBlockingMode] = [:]
    ) -> AutoplayPreferences {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayBlockingModeRawValue: globalMode.rawValue,
            autoplayExceptionsRawValue: exceptions.reduce(into: [:]) { $0[$1.key] = $1.value.rawValue }
        )
        return AutoplayPreferences(persistor: persistor)
    }

    private func makeNavigation(url: URL) -> Navigation {
        Navigation(identity: .init(nil),
                   responders: .init(),
                   state: .started,
                   redirectHistory: [],
                   isCurrent: true,
                   isCommitted: false)
    }

    private func makeExtension(preferences: AutoplayPreferences) -> AutoplayTabExtension {
        AutoplayTabExtension(autoplayPreferences: preferences)
    }

    // MARK: - No reload when modes match

    func testNoReloadWhenEffectiveModeMatchesConfiguredMode() {
        let prefs = makePreferences(globalMode: .blockAudio)
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio
        ext.webViewDidAppear(webView)

        let url = URL(string: "https://example.com")!
        let nav = makeNavigation(url: url)

        // Spy: mediaTypesRequiringUserActionForPlayback should NOT change
        let before = webView.configuration.mediaTypesRequiringUserActionForPlayback
        ext.didStart(nav, url: url)
        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, before)
    }

    // MARK: - Applies exception mode on navigation

    func testAppliesExceptionModeWhenDomainMatchesException() {
        let prefs = makePreferences(globalMode: .blockAudio, exceptions: ["youtube.com": .allowAll])
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio // blockAudio
        ext.webViewDidAppear(webView)

        let url = URL(string: "https://youtube.com/watch?v=test")!
        ext.didStart(makeNavigation(url: url), url: url)

        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, []) // allowAll
    }

    func testWWWStrippedForExceptionLookup() {
        let prefs = makePreferences(globalMode: .blockAudio, exceptions: ["youtube.com": .allowAll])
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio
        ext.webViewDidAppear(webView)

        let url = URL(string: "https://www.youtube.com/watch?v=test")!
        ext.didStart(makeNavigation(url: url), url: url)

        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, []) // allowAll
    }

    func testFallsBackToGlobalWhenNoDomainException() {
        let prefs = makePreferences(globalMode: .blockAll, exceptions: ["other.com": .allowAll])
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio // was blockAudio before
        ext.webViewDidAppear(webView)

        let url = URL(string: "https://youtube.com")!
        ext.didStart(makeNavigation(url: url), url: url)

        // Effective = blockAll (.all), configured was .audio, so it updates
        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, .all) // blockAll
    }

    // MARK: - No reload loop

    func testNoInfiniteReloadOnSecondNavigation() {
        // After first nav adjusts the mode, second nav with same URL should not change it again
        let prefs = makePreferences(globalMode: .blockAudio, exceptions: ["youtube.com": .allowAll])
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio
        ext.webViewDidAppear(webView)

        let url = URL(string: "https://youtube.com")!
        ext.didStart(makeNavigation(url: url), url: url)
        // Now mediaTypes = [] (allowAll), configuredMode = .allowAll

        // Simulate second navigation (as if triggered by the reload)
        let beforeSecondNav = webView.configuration.mediaTypesRequiringUserActionForPlayback
        ext.didStart(makeNavigation(url: url), url: url)
        XCTAssertEqual(webView.configuration.mediaTypesRequiringUserActionForPlayback, beforeSecondNav)
    }

    // MARK: - Settings change while on affected domain

    func testExceptionChangeUpdatesWebViewImmediately() {
        let prefs = makePreferences(globalMode: .blockAudio)
        let ext = makeExtension(preferences: prefs)
        let webView = WKWebView()
        webView.configuration.mediaTypesRequiringUserActionForPlayback = .audio
        ext.webViewDidAppear(webView)

        // Navigate to youtube.com (no exception yet → blockAudio matches)
        let url = URL(string: "https://youtube.com")!
        ext.didStart(makeNavigation(url: url), url: url)
        ext.currentURL = url

        // Now add an exception while already on the page
        let exp = expectation(description: "mediaTypes updated")
        let observer = webView.publisher(for: \.configuration.mediaTypesRequiringUserActionForPlayback)
            .dropFirst()
            .sink { types in
                if types == [] { exp.fulfill() }
            }
        prefs.exceptions["youtube.com"] = .allowAll
        waitForExpectations(timeout: 1)
        withExtendedLifetime(observer) {}
    }
}
```

### Step 2: Run tests to confirm they fail

```bash
xcodebuild test \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "macOS Unit Tests" \
  -only-testing "Unit Tests/AutoplayTabExtensionTests" \
  2>&1 | tail -30
```

Expected: **FAIL** — `AutoplayTabExtension` type not found.

### Step 3: Create `AutoplayTabExtension.swift`

Create `macOS/DuckDuckGo/Tab/TabExtensions/AutoplayTabExtension.swift`:

```swift
//
//  AutoplayTabExtension.swift
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

import Combine
import Navigation
import WebKit

@MainActor
final class AutoplayTabExtension {

    private let autoplayPreferences: AutoplayPreferences
    private weak var webView: WKWebView?
    private var configuredMode: AutoplayBlockingMode
    var currentURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init(autoplayPreferences: AutoplayPreferences) {
        self.autoplayPreferences = autoplayPreferences
        self.configuredMode = autoplayPreferences.autoplayBlockingMode
    }

    func webViewDidAppear(_ webView: WKWebView) {
        self.webView = webView
        subscribeToPreferenceChanges()
    }

    private func subscribeToPreferenceChanges() {
        // React to global mode OR exceptions changes
        autoplayPreferences.$autoplayBlockingMode
            .combineLatest(autoplayPreferences.$exceptions)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.applyModeIfNeeded(for: self?.currentURL)
            }
            .store(in: &cancellables)
    }

    private func applyModeIfNeeded(for url: URL?) {
        guard let webView else { return }
        let effective = url.map { autoplayPreferences.effectiveMode(for: $0) } ?? autoplayPreferences.autoplayBlockingMode
        guard effective != configuredMode else { return }
        configuredMode = effective
        webView.configuration.mediaTypesRequiringUserActionForPlayback = effective.mediaTypesRequiringUserAction
        webView.reload()
    }
}

// MARK: - NavigationResponder

extension AutoplayTabExtension: NavigationResponder {

    func didStart(_ navigation: Navigation, url: URL) {
        currentURL = url
        guard let webView else { return }
        let effective = autoplayPreferences.effectiveMode(for: url)
        guard effective != configuredMode else { return }
        configuredMode = effective
        webView.configuration.mediaTypesRequiringUserActionForPlayback = effective.mediaTypesRequiringUserAction
        // Reload so media policy applies from the start of this page load.
        // configuredMode is already updated above, preventing a reload loop.
        webView.reload()
    }
}

// MARK: - TabExtension

protocol AutoplayExtensionProtocol: AnyObject {}

extension AutoplayTabExtension: TabExtension, AutoplayExtensionProtocol {
    func getPublicProtocol() -> AutoplayExtensionProtocol { self }
}

extension TabExtensions {
    var autoplay: AutoplayExtensionProtocol? {
        extensions.resolve(AutoplayTabExtension.self)
    }
}
```

**Note on `didStart` signature:** Check the exact `NavigationResponder` method signature for URL-based navigation start in the Navigation framework. Look at other extensions like `HistoryTabExtension` to confirm whether the method is `didStart(_ navigation: Navigation)` or receives a URL separately. The URL is available on `navigation.url` — adapt accordingly:

```swift
func didStart(_ navigation: Navigation) {
    guard let url = navigation.url else { return }
    currentURL = url
    // ... rest of logic unchanged
}
```

### Step 4: Run tests to verify they pass

```bash
xcodebuild test \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "macOS Unit Tests" \
  -only-testing "Unit Tests/AutoplayTabExtensionTests" \
  2>&1 | tail -30
```

Expected: all tests **PASS**.

### Step 5: Commit

```bash
git add macOS/UnitTests/Autoplay/AutoplayTabExtensionTests.swift \
        macOS/DuckDuckGo/Tab/TabExtensions/AutoplayTabExtension.swift
git commit -m "feat: add AutoplayTabExtension NavigationResponder for per-site mode enforcement"
```

---

## Task 3: Register `AutoplayTabExtension`

**Files:**
- Modify: `macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift` (dependencies protocol + `registerExtensions`)
- Modify: `macOS/DuckDuckGo/Tab/Model/Tab.swift` (`ExtensionDependencies` struct + where it's populated)

### Step 1: Add `autoplayPreferences` to `TabExtensionDependencies`

In `TabExtensions.swift`, add to the `TabExtensionDependencies` protocol (around line 93, after `webTrackingProtectionPreferences`):

```swift
var autoplayPreferences: AutoplayPreferences { get }
```

### Step 2: Add `autoplayPreferences` to `ExtensionDependencies` in `Tab.swift`

In `Tab.swift`, in the `private struct ExtensionDependencies: TabExtensionDependencies` block (around line 70, after `webTrackingProtectionPreferences`):

```swift
var autoplayPreferences: AutoplayPreferences
```

### Step 3: Populate the field where `ExtensionDependencies` is instantiated

Search for where `ExtensionDependencies(` is called in `Tab.swift`. It will be missing `autoplayPreferences` and fail to compile. Add:

```swift
autoplayPreferences: autoplayPreferences,
```

The `autoplayPreferences` parameter already exists in `Tab.init` (it's the same one used at line 308 for initial WebView config).

### Step 4: Register the extension in `registerExtensions`

In `TabExtensions.swift` `registerExtensions` method, add at the end (before the closing brace, around line 346):

```swift
add {
    AutoplayTabExtension(autoplayPreferences: dependencies.autoplayPreferences)
}
```

**But:** the WebView isn't available at extension init time in this pattern — extensions receive it via `webViewPublisher`. Look at how `SpecialErrorPageTabExtension` or `DuckPlayerTabExtension` handle `webViewFuture`:

```swift
add {
    AutoplayTabExtension(autoplayPreferences: dependencies.autoplayPreferences,
                         webViewPublisher: args.webViewFuture)
}
```

Update `AutoplayTabExtension.init` to accept an optional `webViewPublisher` and subscribe to it:

```swift
init(autoplayPreferences: AutoplayPreferences,
     webViewPublisher: (some Publisher<WKWebView, Never>)? = nil) {
    self.autoplayPreferences = autoplayPreferences
    self.configuredMode = autoplayPreferences.autoplayBlockingMode
    webViewPublisher?.sink { [weak self] wv in
        self?.webViewDidAppear(wv)
    }.store(in: &cancellables)  // Note: store before subscribeToPreferenceChanges
}
```

**Cleaner pattern** (matching other extensions): accept `webViewPublisher` in init and store subscriptions immediately:

```swift
init(autoplayPreferences: AutoplayPreferences,
     webViewPublisher: some Publisher<WKWebView, Never>) {
    self.autoplayPreferences = autoplayPreferences
    self.configuredMode = autoplayPreferences.autoplayBlockingMode
    super.init()  // if NSObject — but class is final, not NSObject, so no super
    // Subscribe to webView
    webViewPublisher
        .sink { [weak self] wv in self?.webViewDidAppear(wv) }
        .store(in: &cancellables)
}
```

Since `AutoplayTabExtension` is `@MainActor`, `cancellables` must be set up carefully. Check if storing in `init` requires `@MainActor` context — it does since the class is `@MainActor`. The `TabExtensionsBuilder.registerExtensions` is also `@MainActor` (note `@MainActor` on that function), so this is fine.

Update the unit test's `makeExtension` accordingly — tests can call `webViewDidAppear` directly without a publisher.

### Step 5: Build to verify

```bash
xcodebuild build \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "DuckDuckGo Privacy Browser" \
  2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: **BUILD SUCCEEDED** (or only pre-existing warnings).

### Step 6: Commit

```bash
git add macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift \
        macOS/DuckDuckGo/Tab/Model/Tab.swift \
        macOS/DuckDuckGo/Tab/TabExtensions/AutoplayTabExtension.swift
git commit -m "feat: register AutoplayTabExtension in tab lifecycle"
```

---

## Task 4: `AutoplayExceptionsSheet.swift`

**Files:**
- Create: `macOS/DuckDuckGo/Preferences/View/AutoplayExceptionsSheet.swift`

### Step 1: Create the SwiftUI sheet

Create `macOS/DuckDuckGo/Preferences/View/AutoplayExceptionsSheet.swift`:

```swift
//
//  AutoplayExceptionsSheet.swift
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

import SwiftUI

struct AutoplayExceptionsSheet: View {

    @ObservedObject var autoplayModel: AutoplayPreferences
    @State private var isAddingDomain = false
    @State private var newDomain = ""
    @State private var newDomainMode: AutoplayBlockingMode = .allowAll
    @Environment(\.dismiss) private var dismiss

    private var sortedDomains: [String] {
        autoplayModel.exceptions.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(UserText.autoplayExceptionsTitle)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // List
            if sortedDomains.isEmpty && !isAddingDomain {
                VStack {
                    Spacer()
                    Text(UserText.autoplayExceptionsEmpty)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(sortedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { autoplayModel.exceptions[domain] ?? .blockAudio },
                                set: { autoplayModel.exceptions[domain] = $0 }
                            )) {
                                ForEach(AutoplayBlockingMode.allCases, id: \.self) { mode in
                                    Text(mode.description).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            Button {
                                autoplayModel.exceptions.removeValue(forKey: domain)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isAddingDomain {
                        addDomainRow
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if !isAddingDomain {
                    Button(UserText.autoplayExceptionsAddWebsite) {
                        newDomain = ""
                        newDomainMode = .allowAll
                        isAddingDomain = true
                    }
                }
                Spacer()
                Button(UserText.autoplayExceptionsDone) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 360)
    }

    @ViewBuilder
    private var addDomainRow: some View {
        HStack {
            TextField(UserText.autoplayExceptionsDomainPlaceholder, text: $newDomain)
                .textFieldStyle(.roundedBorder)

            Picker("", selection: $newDomainMode) {
                ForEach(AutoplayBlockingMode.allCases, id: \.self) { mode in
                    Text(mode.description).tag(mode)
                }
            }
            .labelsHidden()
            .fixedSize()

            Button(UserText.autoplayExceptionsAdd) {
                commitNewDomain()
            }
            .disabled(normalizedDomain.isEmpty)

            Button(UserText.autoplayExceptionsCancel) {
                isAddingDomain = false
            }
        }
    }

    private var normalizedDomain: String {
        var d = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        // strip scheme if pasted
        if let range = d.range(of: "://") { d = String(d[range.upperBound...]) }
        // strip trailing slashes
        d = d.components(separatedBy: "/").first ?? d
        return d
    }

    private func commitNewDomain() {
        let domain = normalizedDomain
        guard !domain.isEmpty else { return }
        autoplayModel.exceptions[domain] = newDomainMode
        isAddingDomain = false
        newDomain = ""
    }
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "DuckDuckGo Privacy Browser" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: **BUILD SUCCEEDED** (or compiler errors only about missing `UserText` keys — those get added in Task 5).

### Step 3: Commit

```bash
git add macOS/DuckDuckGo/Preferences/View/AutoplayExceptionsSheet.swift
git commit -m "feat: add AutoplayExceptionsSheet SwiftUI view"
```

---

## Task 5: Wire sheet into Preferences + `UserText` strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`
- Modify: `macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift`

### Step 1: Add `UserText` strings

Search for `autoplayLabel` in `UserText.swift` to find the right location, then add nearby:

```swift
// Autoplay exceptions sheet
static let autoplayExceptionsTitle = NSLocalizedString("autoplay.exceptions.title", value: "Autoplay Exceptions", comment: "Title of the autoplay exceptions management sheet")
static let autoplayExceptionsEmpty = NSLocalizedString("autoplay.exceptions.empty", value: "No exceptions. Sites will use the default autoplay setting.", comment: "Empty state label in the autoplay exceptions sheet")
static let autoplayExceptionsAddWebsite = NSLocalizedString("autoplay.exceptions.add.website", value: "Add Website", comment: "Button to begin adding a new autoplay exception")
static let autoplayExceptionsDone = NSLocalizedString("autoplay.exceptions.done", value: "Done", comment: "Button to dismiss the autoplay exceptions sheet")
static let autoplayExceptionsDomainPlaceholder = NSLocalizedString("autoplay.exceptions.domain.placeholder", value: "example.com", comment: "Placeholder text for the domain entry field in autoplay exceptions")
static let autoplayExceptionsAdd = NSLocalizedString("autoplay.exceptions.add", value: "Add", comment: "Button to confirm adding a new autoplay exception domain")
static let autoplayExceptionsCancel = NSLocalizedString("autoplay.exceptions.cancel", value: "Cancel", comment: "Button to cancel adding a new autoplay exception domain")
static let autoplayExceptionsManage = NSLocalizedString("autoplay.exceptions.manage", value: "Manage…", comment: "Button label to open the autoplay exceptions sheet")
```

### Step 2: Wire the sheet in `PreferencesGeneralView.swift`

In `PreferencesGeneralView.swift`, add a `@State` variable for sheet presentation at the top of the `GeneralView` body:

```swift
@State private var showingAutoplayExceptions = false
```

Find the Permissions section (around line 304) and add the Exceptions row + sheet modifier:

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
        HStack {
            Text(UserText.autoplayExceptionsTitle)  // "Autoplay Exceptions"
            Spacer()
            Button(UserText.autoplayExceptionsManage) {
                showingAutoplayExceptions = true
            }
        }
    }
}
.sheet(isPresented: $showingAutoplayExceptions) {
    AutoplayExceptionsSheet(autoplayModel: autoplayModel)
}
```

The `.sheet` should be attached at the `PreferencePaneSection` level or the enclosing `VStack` — wherever the existing `CustomHomePageSheet` is attached (check the file for the pattern used by `showingCustomHomePageSheet`).

### Step 3: Build to verify

```bash
xcodebuild build \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "DuckDuckGo Privacy Browser" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: **BUILD SUCCEEDED**.

### Step 4: Commit

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift \
        macOS/DuckDuckGo/Preferences/View/PreferencesGeneralView.swift
git commit -m "feat: wire autoplay exceptions sheet into General Settings permissions"
```

---

## Task 6: Register new files in `project.pbxproj` + full test run

**Files:**
- Modify: `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`

### Step 1: Add files to Xcode project

Open the project in Xcode and add the two new Swift files to the appropriate targets:

- `macOS/DuckDuckGo/Tab/TabExtensions/AutoplayTabExtension.swift` → main app target + App Store target
- `macOS/DuckDuckGo/Preferences/View/AutoplayExceptionsSheet.swift` → main app target + App Store target
- `macOS/UnitTests/Autoplay/AutoplayTabExtensionTests.swift` → Unit Tests target

Alternatively, edit `project.pbxproj` directly using the same pattern as existing entries. Find another `.swift` file in the same directories and duplicate its `PBXBuildFile` and `PBXFileReference` entries with fresh UUIDs.

**Note:** The Xcode GUI approach (drag-and-drop into project navigator, check "Add to targets") is less error-prone for `project.pbxproj`.

### Step 2: Build both configurations

```bash
xcodebuild build \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "DuckDuckGo Privacy Browser" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: **BUILD SUCCEEDED**.

### Step 3: Run all autoplay tests

```bash
xcodebuild test \
  -project macOS/DuckDuckGo-macOS.xcodeproj \
  -scheme "macOS Unit Tests" \
  -only-testing "Unit Tests/AutoplayPreferencesTests" \
  -only-testing "Unit Tests/AutoplayExceptionsTests" \
  -only-testing "Unit Tests/AutoplayTabExtensionTests" \
  2>&1 | tail -40
```

Expected: all tests **PASS**.

### Step 4: Commit

```bash
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "chore: register AutoplayTabExtension and AutoplayExceptionsSheet in Xcode project"
```

---

## Manual Smoke Test

1. Build and run the app
2. Open **Settings → General → Permissions**
3. Verify an **"Autoplay Exceptions"** row with a **"Manage…"** button appears below the autoplay picker
4. Click **"Manage…"** — sheet opens with empty state text
5. Click **"Add Website"** → type `youtube.com`, pick **"Video and audio"** → click **Add**
6. Confirm the row appears in the list
7. Set global mode to **"Block audio"**
8. Navigate to `https://youtube.com` — video should autoplay (exception overrides global)
9. Navigate to a different site — global **"Block audio"** applies (no autoplay)
10. Return to exceptions sheet, remove `youtube.com`
11. Navigate back to `youtube.com` — global **"Block audio"** applies again
12. Verify no reload loop: navigate to youtube.com once, observe exactly one page load in the network tab
