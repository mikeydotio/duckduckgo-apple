# Duck.ai Voice Toolbar Shortcut — Design Spec

**Date:** 2026-03-23
**Platform:** macOS
**Scope:** PoC — minimal implementation to validate the entry point

---

## Goal

Add a pinnable button to the macOS navigation bar (right of the address bar, alongside VPN/passwords/downloads) that opens duck.ai in voice mode in a new tab with one click.

URL: `https://duck.ai/?mode=voice-mode`

---

## Design Decisions

- **PoC-first:** no URL constant in `AppURLs`, no icons provider protocol extension — these are deferred to productionisation.
- **Unpinned by default:** users who have the flag on won't see the button until they right-click the overflow menu and pin it.
- **Feature-flagged:** hidden entirely when the flag is off.
- **No popover, no model:** the button just navigates. No `NavBarButtonModel` class is needed.

---

## Components & Changes

### 1. Feature Flag — `FeatureFlag.swift`

Add a new case to the `FeatureFlag` enum:

```swift
case duckAIVoiceShortcut
```

Disabled by default (internal rollout only for PoC).

---

### 2. PinningManager — `PinningManager.swift`

Add `.duckAIVoice` to `PinnableView`:

```swift
case duckAIVoice
```

Add a `shortcutTitle` case:

```swift
case .duckAIVoice:
    return isPinned(.duckAIVoice) ? UserText.hideDuckAIVoiceShortcut : UserText.showDuckAIVoiceShortcut
```

No `pin()` call on first launch — unpinned by default.

Also update `MockPinningManager` (DEBUG-only) to handle the new case if required by the compiler.

---

### 3. Localisation — `UserText.swift`

Add two strings:

```swift
static let showDuckAIVoiceShortcut = NSLocalizedString("show.duck.ai.voice.shortcut", value: "Show Duck.ai Voice", comment: "Menu item to pin the Duck.ai voice button to the toolbar")
static let hideDuckAIVoiceShortcut = NSLocalizedString("hide.duck.ai.voice.shortcut", value: "Hide Duck.ai Voice", comment: "Menu item to unpin the Duck.ai voice button from the toolbar")
```

---

### 4. NavigationBarViewController — Storyboard + Swift

#### Storyboard (`NavigationBar.storyboard`)

- Add a `MouseOverButton` to the `menuButtons` NSStackView, positioned alongside the existing pinnable buttons.
- Wire the outlet `duckAIVoiceButton`.
- Wire width and height constraints (`duckAIVoiceButtonWidthConstraint`, `duckAIVoiceButtonHeightConstraint`) using the same sizing as `vpnButtonWidthConstraint` / `vpnButtonHeightConstraint`.
- Wire the action `duckAIVoiceButtonAction`.

#### `NavigationBarViewController.swift`

**Outlets:**
```swift
@IBOutlet private var duckAIVoiceButton: MouseOverButton!
@IBOutlet private var duckAIVoiceButtonWidthConstraint: NSLayoutConstraint!
@IBOutlet private var duckAIVoiceButtonHeightConstraint: NSLayoutConstraint!
```

**Setup** (called from `viewDidLoad` alongside `setupNetworkProtectionButton()`):
```swift
private func setupDuckAIVoiceButton() {
    guard featureFlagger.isFeatureOn(.duckAIVoiceShortcut) else {
        duckAIVoiceButton.isHidden = true
        return
    }

    let menuItem = NSMenuItem(
        title: pinningManager.shortcutTitle(for: .duckAIVoice),
        action: #selector(toggleDuckAIVoicePinning),
        target: self
    )
    duckAIVoiceButton.menu = NSMenu(items: [menuItem])
    duckAIVoiceButton.image = DesignSystemImages.Glyphs.Size16.microphone
    duckAIVoiceButton.isHidden = !pinningManager.isPinned(.duckAIVoice)

    // Keep menu item title in sync
    NotificationCenter.default.addObserver(
        forName: .PinnedViewsChanged,
        object: nil,
        queue: .main
    ) { [weak self, weak menuItem] _ in
        guard let self else { return }
        menuItem?.title = self.pinningManager.shortcutTitle(for: .duckAIVoice)
        self.duckAIVoiceButton.isHidden = !self.pinningManager.isPinned(.duckAIVoice)
    }
}
```

**Pin toggle:**
```swift
@objc private func toggleDuckAIVoicePinning(_ sender: NSMenuItem) {
    pinningManager.togglePinning(for: .duckAIVoice)
}
```

**Action:**
```swift
@IBAction func duckAIVoiceButtonAction(_ sender: NSButton) {
    guard let url = URL(string: "https://duck.ai/?mode=voice-mode") else { return }
    showTab(.aiChat(url))
}
```

**Button sizing** (in `setupNavigationButtonsSize()`):
```swift
duckAIVoiceButtonWidthConstraint.constant = addressBarStyleProvider.addressBarButtonSize
duckAIVoiceButtonHeightConstraint.constant = addressBarStyleProvider.addressBarButtonSize
```

**`ensureObjectDeallocated` guard** (in `deinit`):
```swift
duckAIVoiceButton.ensureObjectDeallocated(after: 1.0, do: .interrupt)
```

---

## Out of Scope (PoC)

- Pixel firing
- URL constant in `AppURLs`
- Icon added to `NavigationToolbarIconsProviding` protocol
- Theme-aware icon (legacy vs current icons provider)
- Unit tests
- Accessibility identifier / tooltip

---

## Files Changed

| File | Change |
|------|--------|
| `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift` | Add `case duckAIVoiceShortcut` |
| `macOS/DuckDuckGo/NavigationBar/PinningManager.swift` | Add `case duckAIVoice` to `PinnableView`, `shortcutTitle` case |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` (macOS) | Add show/hide strings |
| `macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift` | Outlets, setup, action, sizing, deinit guard |
| `macOS/DuckDuckGo/NavigationBar/View/NavigationBar.storyboard` | New button, constraints, outlet + action wiring |
