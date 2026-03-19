# Per-Site Autoplay Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to override the global autoplay policy on a per-website basis via the Permission Center.

**Architecture:** Add `case autoplayPolicy` to `PermissionType`, store per-site overrides in the existing `PermissionManager` (CoreData-backed), resolve per-site vs global in `AutoplayPolicyTabExtension`, and display a custom 4-option row in `PermissionCenterView`.

**Tech Stack:** Swift, SwiftUI, WebKit private API, CoreData (via existing PermissionStore)

**Spec:** `docs/superpowers/specs/2026-03-19-per-site-autoplay-policy-design.md`

---

### Task 1: Add `autoplayPolicy` case to `PermissionType`

**Files:**
- Modify: `macOS/DuckDuckGo/Permissions/Model/PermissionType.swift`

- [ ] **Step 1: Add the constant and enum case**

In `PermissionType`, add `autoplayPolicy` constant to the `Constants` enum and add the case:

```swift
// In Constants enum, add:
case autoplayPolicy = "autoplay_policy"

// In PermissionType enum, add after `notification`:
case autoplayPolicy
```

- [ ] **Step 2: Add rawValue and init**

In `rawValue` computed property, add:
```swift
case .autoplayPolicy: return Constants.autoplayPolicy.rawValue
```

In `init?(rawValue:)`, add a case before the `default`:
```swift
case Constants.autoplayPolicy.rawValue: self = .autoplayPolicy
```

- [ ] **Step 3: Update `canPersistGrantedDecision`**

Add `.autoplayPolicy` to all 4 switch sites (2 methods x 2 feature flag branches). In `canPersistGrantedDecision`:
- `if` branch (line 83): add `.autoplayPolicy` to the `true` case
- `else` branch (line 88): add `.autoplayPolicy` to the `true` case

- [ ] **Step 4: Update `canPersistDeniedDecision`**

In `canPersistDeniedDecision`:
- `if` branch (line 99): add `.autoplayPolicy` to the `true` case
- `else` branch (line 106): add `.autoplayPolicy` to the `true` case

- [ ] **Step 5: Update icon properties**

In `icon` (line 129), add:
```swift
case .autoplayPolicy:
    return DesignSystemImages.Glyphs.Size16.audio
```

In `solidIcon` (line 147), add `.autoplayPolicy` to the `nil` case:
```swift
case .notification, .popups, .externalScheme, .autoplayPolicy:
    return nil
```

- [ ] **Step 6: Update `requiresSystemPermission`**

Add `.autoplayPolicy` to the `false` case (line 165):
```swift
case .camera, .microphone, .popups, .externalScheme, .autoplayPolicy:
    return false
```

- [ ] **Step 7: Update auth view files for new PermissionType case**

Two separate files need updates:

**A.** In `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift` (line 24), the `localizedDescription` switch on `PermissionType` needs a new case:
```swift
case .autoplayPolicy:
    return UserText.permissionAutoplay
```

**B.** In `macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift`, the `PermissionAuthorizationType.init(from:)` method (line 44) has an exhaustive switch on `PermissionType` that will break. Add a case for `.autoplayPolicy` — since autoplay never goes through the authorization flow, use an assertion:
```swift
case .autoplayPolicy:
    assertionFailure("Autoplay policy does not use authorization flow")
    self = .camera // fallback, shouldn't happen
```

Note: The `localizedDescription` in `PermissionAuthorizationSwiftUIView.swift` is on `PermissionAuthorizationType` (a separate enum), NOT `PermissionType` — do not modify it.

- [ ] **Step 8: Verify the project builds**

Run: `xcodebuild build -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -20`

Fix any remaining exhaustive switch compiler errors by adding `.autoplayPolicy` to the appropriate existing cases.

- [ ] **Step 9: Commit**

```bash
git add macOS/DuckDuckGo/Permissions/Model/PermissionType.swift macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationViewController.swift macOS/DuckDuckGo/Permissions/View/PermissionAuthorizationSwiftUIView.swift
git commit -m "Add autoplayPolicy case to PermissionType"
```

---

### Task 2: Add UserText strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`

- [ ] **Step 1: Add autoplay permission strings**

Add near the existing autoplay strings (around line 1123):
```swift
static let permissionAutoplay = NSLocalizedString("permission.autoplay", value: "Autoplay", comment: "Display name for the autoplay permission type in Permission Center")
static let permissionAutoplayUseDefault = NSLocalizedString("permission.autoplay.use-default", value: "Use default", comment: "Autoplay permission option: use the global default setting")
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift
git commit -m "Add UserText strings for autoplay permission"
```

---

### Task 3: Add `AutoplayDecision` enum and view model support

**Files:**
- Modify: `macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift`

- [ ] **Step 1: Add `AutoplayDecision` enum**

Add after the `PopupDecision` enum (line 140):
```swift
/// Autoplay decision options for the Permission Center dropdown
enum AutoplayDecision: Hashable {
    case useDefault
    case allowAll
    case audioMuted
    case blockAll
}
```

- [ ] **Step 2: Add `setAutoplayDecision` method**

Add after the `setPopupDecision` method (around line 339):
```swift
/// Updates the autoplay decision for the current domain
func setAutoplayDecision(_ decision: AutoplayDecision) {
    switch decision {
    case .useDefault:
        permissionManager.removePermission(forDomain: domain, permissionType: .autoplayPolicy)
    case .allowAll:
        permissionManager.setPermission(.allow, forDomain: domain, permissionType: .autoplayPolicy)
    case .audioMuted:
        permissionManager.setPermission(.ask, forDomain: domain, permissionType: .autoplayPolicy)
    case .blockAll:
        permissionManager.setPermission(.deny, forDomain: domain, permissionType: .autoplayPolicy)
    }

    // Update the item's decision in the list
    if let index = permissionItems.firstIndex(where: { $0.permissionType == .autoplayPolicy }) {
        switch decision {
        case .useDefault: permissionItems[index].decision = .ask
        case .allowAll: permissionItems[index].decision = .allow
        case .audioMuted: permissionItems[index].decision = .ask
        case .blockAll: permissionItems[index].decision = .deny
        }
    }

    markReloadNeeded()
}
```

- [ ] **Step 3: Add `currentAutoplayDecision` method**

Add after `setAutoplayDecision`:
```swift
/// Returns the current autoplay decision based on whether a per-site override is persisted
func currentAutoplayDecision() -> AutoplayDecision {
    guard permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: .autoplayPolicy) else {
        return .useDefault
    }
    let decision = permissionManager.permission(forDomain: domain, permissionType: .autoplayPolicy)
    switch decision {
    case .allow: return .allowAll
    case .ask: return .audioMuted
    case .deny: return .blockAll
    }
}
```

- [ ] **Step 4: Inject autoplay row in `collectPermissions()`**

In `collectPermissions()` (line 406), add after the `pageInitiatedPopupOpened` block (after line 425):
```swift
// Always include autoplay policy when feature flag is on
if featureFlagger.isFeatureOn(.autoplayPolicy),
   !otherPermissions.contains(.autoplayPolicy),
   !removedPermissions.contains(.autoplayPolicy) {
    otherPermissions.append(.autoplayPolicy)
}
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -20`

- [ ] **Step 6: Commit**

```bash
git add macOS/DuckDuckGo/Permissions/ViewModel/PermissionCenterViewModel.swift
git commit -m "Add AutoplayDecision enum and view model support"
```

---

### Task 4: Add `AutoplayPermissionRowView` to Permission Center

**Files:**
- Modify: `macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift`

- [ ] **Step 1: Add `case .autoplayPolicy` to the ForEach switch**

In `PermissionCenterView.swift`, in the `ForEach` block (line 78), add a case before `default`:
```swift
case .autoplayPolicy:
    AutoplayPermissionRowView(
        item: item,
        currentDecision: viewModel.currentAutoplayDecision(),
        onDecisionChanged: { decision in
            viewModel.setAutoplayDecision(decision)
        }
    )
```

- [ ] **Step 2: Create `AutoplayPermissionRowView`**

Add the new view struct in the same file, following the pattern of `PopupPermissionRowView`:
```swift
/// Row view for the autoplay permission in Permission Center
struct AutoplayPermissionRowView: View {
    let item: PermissionCenterItem
    let currentDecision: AutoplayDecision
    let onDecisionChanged: (AutoplayDecision) -> Void

    @State private var selectedDecision: AutoplayDecision
    @State private var isHovering = false

    init(item: PermissionCenterItem, currentDecision: AutoplayDecision, onDecisionChanged: @escaping (AutoplayDecision) -> Void) {
        self.item = item
        self.currentDecision = currentDecision
        self.onDecisionChanged = onDecisionChanged
        self._selectedDecision = State(initialValue: currentDecision)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.permissionType.icon)
                .foregroundColor(Color(designSystemColor: .iconSecondary))
                .frame(width: 16, height: 16)

            Text(UserText.permissionAutoplay)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Spacer()

            Picker("", selection: $selectedDecision) {
                Text(UserText.permissionAutoplayUseDefault).tag(AutoplayDecision.useDefault)
                Text(UserText.autoplayModeAllowAll).tag(AutoplayDecision.allowAll)
                Text(UserText.autoplayModeBlockAudio).tag(AutoplayDecision.audioMuted)
                Text(UserText.autoplayModeBlockAll).tag(AutoplayDecision.blockAll)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: selectedDecision) { newValue in
                onDecisionChanged(newValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovering ? Color(designSystemColor: .hoverBackground) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -20`

Adjust styling to match existing row views (check `PermissionRowView` for exact padding, font, spacing, hover background color).

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Permissions/View/PermissionCenterView.swift
git commit -m "Add AutoplayPermissionRowView to Permission Center"
```

---

### Task 5: Wire `PermissionManager` into `AutoplayPolicyTabExtension`

**Files:**
- Modify: `macOS/DuckDuckGo/Tab/Navigation/AutoplayPolicyTabExtension.swift`
- Modify: `macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift` (line 208-210)

- [ ] **Step 1: Add `permissionManager` dependency to `AutoplayPolicyTabExtension`**

```swift
final class AutoplayPolicyTabExtension {

    private let autoplayPreferences: AutoplayPreferences
    private let featureFlagger: FeatureFlagger
    private let permissionManager: PermissionManagerProtocol

    init(autoplayPreferences: AutoplayPreferences, featureFlagger: FeatureFlagger, permissionManager: PermissionManagerProtocol) {
        self.autoplayPreferences = autoplayPreferences
        self.featureFlagger = featureFlagger
        self.permissionManager = permissionManager
    }
}
```

- [ ] **Step 2: Update `decidePolicy` with per-site resolution**

```swift
@MainActor
func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
    guard featureFlagger.isFeatureOn(.autoplayPolicy) else { return .next }

    let domain = navigationAction.url.host ?? ""

    if permissionManager.hasPermissionPersisted(forDomain: domain, permissionType: .autoplayPolicy) {
        let decision = permissionManager.permission(forDomain: domain, permissionType: .autoplayPolicy)
        switch decision {
        case .allow:
            preferences.autoplayPolicy = .allow
        case .ask:
            preferences.autoplayPolicy = .allowWithoutSound
        case .deny:
            preferences.autoplayPolicy = .deny
        }
    } else {
        preferences.autoplayPolicy = .init(autoplayPreferences.autoplayBlockingMode.mediaTypesRequiringUserAction)
    }

    return .next
}
```

- [ ] **Step 3: Pass `permissionManager` in `TabExtensionsBuilder`**

In `macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift`, update the `add` block for `AutoplayPolicyTabExtension` (line 208-210). The `permissionManager` is available via `args.permissionModel` — but `PermissionModel.permissionManager` is private. Instead, add `permissionManager` to the `TabExtensionDependencies` protocol and `ExtensionDependencies` struct.

In `TabExtensionDependencies` protocol (line 73), add:
```swift
var permissionManager: PermissionManagerProtocol { get }
```

In `ExtensionDependencies` struct in `Tab.swift` (line 51), add:
```swift
var permissionManager: PermissionManagerProtocol
```

In `Tab.swift` where `ExtensionDependencies` is constructed (line 343), add the `permissionManager` parameter:
```swift
permissionManager: permissionManager,
```

Then update the builder:
```swift
add {
    AutoplayPolicyTabExtension(
        autoplayPreferences: dependencies.autoplayPreferences,
        featureFlagger: dependencies.featureFlagger,
        permissionManager: dependencies.permissionManager
    )
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Tab/Navigation/AutoplayPolicyTabExtension.swift macOS/DuckDuckGo/Tab/TabExtensions/TabExtensions.swift macOS/DuckDuckGo/Tab/Model/Tab.swift
git commit -m "Wire PermissionManager into AutoplayPolicyTabExtension for per-site resolution"
```

---

### Task 6: Show Permission Center icon on address bar hover

**Files:**
- Modify: `macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift`

- [ ] **Step 1: Update `shouldShowPermissionCenterButton` signature and logic**

In the `TabViewModel` extension (line 2857), add `isMouseOverNavigationBar` parameter and update the return condition:

```swift
func shouldShowPermissionCenterButton(
    isTextFieldEditorFirstResponder: Bool,
    hasAnyPersistedPermissions: Bool,
    isMouseOverNavigationBar: Bool = false,
    isAutoplayFeatureOn: Bool = false
) -> Bool {
    let hasRequestedPermission = usedPermissions.values.contains(where: { $0.isRequested })
    let shouldShowWhileFocused = (tab.content == .newtab) && hasRequestedPermission
    let isAnyPermissionPresent = !usedPermissions.values.isEmpty
    let pageInitiatedPopupOpened = tab.popupHandling?.pageInitiatedPopupOpened ?? false

    return (shouldShowWhileFocused
        || (!isTextFieldEditorFirstResponder && (isAnyPermissionPresent || pageInitiatedPopupOpened || hasAnyPersistedPermissions))
        || (!isTextFieldEditorFirstResponder && isMouseOverNavigationBar && isAutoplayFeatureOn))
    && !isShowingErrorPage
}
```

- [ ] **Step 2: Update the caller in `updatePermissionCenterButton()`**

At line 844, pass the new parameters:
```swift
permissionCenterButton.isShown = tabViewModel.shouldShowPermissionCenterButton(
    isTextFieldEditorFirstResponder: isTextFieldEditorFirstResponder,
    hasAnyPersistedPermissions: hasAnyPersistedPermissions,
    isMouseOverNavigationBar: isMouseOverNavigationBar,
    isAutoplayFeatureOn: featureFlagger.isFeatureOn(.autoplayPolicy)
)
```

- [ ] **Step 3: Trigger `updatePermissionCenterButton` on hover changes**

In the `isMouseOverNavigationBar` property's `didSet` (line 252), add a call to update the permission center button:
```swift
var isMouseOverNavigationBar = false {
    didSet {
        if isMouseOverNavigationBar != oldValue {
            updateBookmarkButtonVisibility()
            updatePermissionCenterButton()
        }
    }
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -20`

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/NavigationBar/View/AddressBarButtonsViewController.swift
git commit -m "Show Permission Center icon on address bar hover when autoplay feature is on"
```

---

### Task 7: Tests

**Files:**
- Modify: `macOS/UnitTests/Preferences/AutoplayPreferencesTests.swift`
- Check for existing: `macOS/UnitTests/Permissions/PermissionModelTests.swift`, `macOS/UnitTests/Permissions/PermissionCenterViewModelTests.swift`

- [ ] **Step 1: Find existing test files and mock patterns**

Check what test infrastructure exists:
- Look for `MockPermissionManager` or `TestPermissionManager` in the test directory
- Look for existing `PermissionCenterViewModelTests`
- Check how `MockFeatureFlagger` works

Run: Search for these in `macOS/UnitTests/`

- [ ] **Step 2: Write `AutoplayPolicyTabExtension` tests**

Create or modify the test file for `AutoplayPolicyTabExtension`. Test:
1. When no per-site override exists, uses global `autoplayPreferences.autoplayBlockingMode`
2. When per-site `.allow` is stored, maps to `.allow` policy
3. When per-site `.ask` is stored, maps to `.allowWithoutSound` policy
4. When per-site `.deny` is stored, maps to `.deny` policy
5. When feature flag is off, returns `.next` without setting policy

- [ ] **Step 3: Write `PermissionCenterViewModel` autoplay tests**

Test:
1. Autoplay row appears in `permissionItems` when feature flag is on
2. Autoplay row does NOT appear when feature flag is off
3. `setAutoplayDecision(.useDefault)` calls `removePermission`
4. `setAutoplayDecision(.allowAll)` stores `.allow`
5. `setAutoplayDecision(.audioMuted)` stores `.ask`
6. `setAutoplayDecision(.blockAll)` stores `.deny`
7. `currentAutoplayDecision()` returns `.useDefault` when no permission persisted
8. `currentAutoplayDecision()` returns correct enum for each persisted decision

- [ ] **Step 4: Write `PermissionType` round-trip test**

Test that `PermissionType(rawValue: "autoplay_policy")` returns `.autoplayPolicy` and that `.autoplayPolicy.rawValue` returns `"autoplay_policy"`.

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -project macOS/DuckDuckGo-macOS.xcodeproj -scheme DuckDuckGo\ Privacy\ Browser -destination 'platform=macOS' -quiet 2>&1 | tail -40`

- [ ] **Step 6: Commit**

```bash
git add macOS/UnitTests/
git commit -m "Add tests for per-site autoplay policy"
```
