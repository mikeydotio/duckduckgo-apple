# View All Chats — Native Address Bar Omnibar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "View all chats" footer row to the duck.ai address bar suggestions list that appears when the user has more than 5 chats, opening a new duck.ai tab when clicked or keyboard-selected.

**Architecture:** The `AIChatSuggestionsViewModel` is extended with a `showViewAllChats` flag that drives a new `AIChatViewAllChatsRowView` appended by `AIChatSuggestionsView`. The controller detects overflow by fetching `maxHistoryCount + 1` chats; if the result exceeds the cap, it sets the flag. Keyboard navigation in the ViewModel is extended to include the footer row as a virtual last index.

**Tech Stack:** Swift, AppKit (NSView, NSStackView, NSTextField, NSImageView), Combine (`@Published`), `DesignResourcesKitIcons` for icons, `KeyboardShortcutView` for key caps.

**Spec:** `docs/superpowers/specs/2026-04-07-view-all-chats-native-omnibar-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift` | Modify | Add `viewAllChatsNativeOmnibar` subfeature |
| `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift` | Modify | Add `aiChatViewAllChatsNativeOmnibar` flag + config |
| `SharedPackages/AIChat/Sources/AIChat/Shared/Suggestions/AIChatSuggestionsViewModel.swift` | Modify | `showViewAllChats`, `isViewAllChatsSelected`, keyboard nav, `clearAllChats` |
| `macOS/DuckDuckGo/AIChat/Suggestions/AIChatViewAllChatsRowView.swift` | **Create** | Footer row UI: icon, label, keyboard shortcut view, "Open Duck.ai" label, arrow |
| `macOS/DuckDuckGo/AIChat/Suggestions/AIChatSuggestionsView.swift` | Modify | Append footer row, `onViewAllChatsClicked`, height calculation, `bind` subscription |
| `macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift` | Modify | Over-fetch, set `showViewAllChats`, `viewAllChats()`, `submitSelectedSuggestion` guard |
| `macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift` | Modify | Wire `onViewAllChatsClicked` in `setupSuggestionsView()` |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` | Modify | Add `aiChatViewAllChats` and `aiChatOpenDuckAI` strings |

---

## Task 1: Feature Flags

**Files:**
- Modify: `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`
- Modify: `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`

- [ ] **Step 1: Add the subfeature case to `AIChatSubfeature`**

In `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`, find the `AIChatSubfeature` enum (around line 321). Add after `sidebarAboutSchemeNavigationFix`:

```swift
    /// Enables "View all chats" row at the bottom of AI chat suggestions in the native address bar omnibar
    case viewAllChatsNativeOmnibar
```

- [ ] **Step 2: Add the feature flag case**

In `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`, find `case aiChatNativeStorage` (the last AI chat flag case) and add before it:

```swift
    /// Enables "View all chats" footer row in the duck.ai address bar suggestions list
    case aiChatViewAllChatsNativeOmnibar
```

- [ ] **Step 3: Add the flag config**

In the same file, find `case .aiChatRemoveSuggestion:` in the large config switch and add alongside it:

```swift
        case .aiChatViewAllChatsNativeOmnibar:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AIChatSubfeature.viewAllChatsNativeOmnibar)), category: .duckAI)
```

- [ ] **Step 4: Commit**

```bash
git add SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift
git add macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift
git commit -m "Add aiChatViewAllChatsNativeOmnibar feature flag"
```

---

## Task 2: ViewModel — `showViewAllChats` and keyboard navigation

**Files:**
- Modify: `SharedPackages/AIChat/Sources/AIChat/Shared/Suggestions/AIChatSuggestionsViewModel.swift`

- [ ] **Step 1: Add `showViewAllChats` published property and `isViewAllChatsSelected`**

In `AIChatSuggestionsViewModel`, add after the `isKeyboardNavigating` published property (around line 45):

```swift
    /// Whether the "View all chats" footer row should be shown below the suggestions.
    /// Set by the controller when it detects more chats than the display cap.
    @Published public var showViewAllChats: Bool = false
```

And after the `selectedSuggestion` computed property (around line 60):

```swift
    /// True when the virtual "view all" row is selected.
    /// The virtual row's index is `filteredSuggestions.count` (one past the last suggestion).
    public var isViewAllChatsSelected: Bool {
        showViewAllChats && selectedIndex == filteredSuggestions.count
    }
```

- [ ] **Step 2: Update `selectNext()` to include the virtual footer row**

In `selectNext()`, replace the block after `if let currentIndex = selectedIndex {`:

```swift
        if let currentIndex = selectedIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < filteredSuggestions.count {
                selectedIndex = nextIndex
                return true
            } else if showViewAllChats && nextIndex == filteredSuggestions.count {
                selectedIndex = nextIndex  // land on "view all" virtual row
                return true
            }
            return false
        } else {
            selectedIndex = 0
            return true
        }
```

- [ ] **Step 3: Update `clearAllChats()` to reset `showViewAllChats`**

In `clearAllChats()`, add `showViewAllChats = false` alongside the other resets:

```swift
    public func clearAllChats() {
        selectedIndex = nil
        isKeyboardNavigating = false
        filteredSuggestions = []
        showViewAllChats = false
    }
```

- [ ] **Step 4: Update `setChats()` selection clamp to account for the virtual row**

In `setChats(pinned:recent:)`, after `filteredSuggestions = Array(allChats.prefix(maxSuggestions))`, update the selection clamp:

```swift
        // Reset selection if it's now out of bounds.
        // The valid range is 0..<filteredSuggestions.count when showViewAllChats is false,
        // or 0...filteredSuggestions.count when showViewAllChats is true (virtual row).
        if let index = selectedIndex {
            let maxValidIndex = filteredSuggestions.isEmpty ? -1 : filteredSuggestions.count - 1 + (showViewAllChats ? 1 : 0)
            if index > maxValidIndex {
                selectedIndex = filteredSuggestions.isEmpty ? nil : maxValidIndex
            }
        }
```

- [ ] **Step 5: Update `removeSuggestion()` selection clamp similarly**

In `removeSuggestion(_:)`, after `filteredSuggestions.removeAll { $0.id == suggestion.id }`:

```swift
        if let index = selectedIndex {
            let maxValidIndex = filteredSuggestions.isEmpty ? -1 : filteredSuggestions.count - 1 + (showViewAllChats ? 1 : 0)
            if index > maxValidIndex {
                selectedIndex = filteredSuggestions.isEmpty ? nil : maxValidIndex
            }
        }
```

- [ ] **Step 6: Add `selectViewAllChats()` for mouse hover on the footer row**

`select(at:)` guards against out-of-bounds indices, so hovering the footer row needs its own method. Add after `select(at:)`:

```swift
    /// Selects the "view all" virtual row from mouse hover.
    public func selectViewAllChats() {
        guard showViewAllChats else { return }
        isKeyboardNavigating = false
        selectedIndex = filteredSuggestions.count
    }
```

- [ ] **Step 8: Commit**

```bash
git add SharedPackages/AIChat/Sources/AIChat/Shared/Suggestions/AIChatSuggestionsViewModel.swift
git commit -m "Extend AIChatSuggestionsViewModel with showViewAllChats and virtual footer row navigation"
```

---

## Task 3: Create `AIChatViewAllChatsRowView`

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`
- Create: `macOS/DuckDuckGo/AIChat/Suggestions/AIChatViewAllChatsRowView.swift`

- [ ] **Step 1: Add `UserText` strings first** (the new file references them — must compile before the file is added to the project)

In `macOS/DuckDuckGo/Common/Localizables/UserText.swift`, find the AI chat section (near `aiChatOpenSidebarButton`) and add:

```swift
    static let aiChatViewAllChats = NSLocalizedString(
        "aichat.suggestions.view-all-chats",
        value: "View all chats",
        comment: "Footer row label in the duck.ai address bar suggestions list, opens full chat history in duck.ai"
    )

    static let aiChatOpenDuckAI = NSLocalizedString(
        "aichat.suggestions.open-duck-ai",
        value: "Open Duck.ai",
        comment: "Right-side label on the 'View all chats' footer row in duck.ai address bar suggestions"
    )
```

- [ ] **Step 3: Create the file**

Create `macOS/DuckDuckGo/AIChat/Suggestions/AIChatViewAllChatsRowView.swift` with this content:

```swift
//
//  AIChatViewAllChatsRowView.swift
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

import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// Footer row displayed below AI chat suggestions when there are more chats than the display cap.
/// Mirrors the visual style of the "Ask privately" row in the search address bar, with a
/// keyboard shortcut indicator and "Open Duck.ai" label anchored to the trailing edge.
final class AIChatViewAllChatsRowView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 6
        static let rightSideSpacing: CGFloat = 4     // spacing between shortcut view, label, arrow
        static let rightSideTrailingPadding: CGFloat = 8

        static let iconColor: NSColor = .suggestionIcon
        static let textColor: NSColor = NSColor(designSystemColor: .textPrimary)
        static let labelFontSize: CGFloat = 11
    }

    // MARK: - UI Components

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.aiChatHistory
        imageView.contentTintColor = Constants.iconColor
        return imageView
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatViewAllChats)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let keyboardShortcutView: KeyboardShortcutView = {
        let view = KeyboardShortcutView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: ["↑", "↓"])
        view.toolTip = "up / down arrow"
        return view
    }()

    private let openDuckAILabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatOpenDuckAI)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.labelFontSize, weight: .semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let arrowImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    private let backgroundLayer = CALayer()

    // MARK: - Properties

    private let themeProvider: SuggestionRowThemeProviding
    private var trackingArea: NSTrackingArea?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isHovered: Bool = false {
        didSet { updateAppearance() }
    }

    var isKeyboardNavigating: Bool = false

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onMouseMoved: (() -> Void)?

    // MARK: - Initialization

    init(themeProvider: SuggestionRowThemeProviding = DefaultSuggestionRowThemeProvider()) {
        self.themeProvider = themeProvider
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        backgroundLayer.cornerRadius = themeProvider.suggestionHighlightCornerRadius
        layer?.insertSublayer(backgroundLayer, at: 0)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(keyboardShortcutView)
        addSubview(openDuckAILabel)
        addSubview(arrowImageView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.rowHeight),

            // Left: icon
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            // Left: title (fills space between icon and right side)
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: keyboardShortcutView.leadingAnchor, constant: -Constants.iconTitleSpacing),

            // Right: arrow (anchored to trailing)
            arrowImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.rightSideTrailingPadding),
            arrowImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            arrowImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            // Right: "Open Duck.ai" label (left of arrow)
            openDuckAILabel.trailingAnchor.constraint(equalTo: arrowImageView.leadingAnchor, constant: -Constants.rightSideSpacing),
            openDuckAILabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Right: keyboard shortcut view (left of label)
            keyboardShortcutView.trailingAnchor.constraint(equalTo: openDuckAILabel.leadingAnchor, constant: -Constants.rightSideSpacing),
            keyboardShortcutView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let isHighlighted = isSelected || isHovered
        keyboardShortcutView.isHighlighted = isHighlighted

        if isHighlighted {
            let tintColor = themeProvider.selectedTintColor
            backgroundLayer.backgroundColor = themeProvider.accentPrimaryColor.cgColor
            titleLabel.textColor = tintColor
            iconImageView.contentTintColor = tintColor
            openDuckAILabel.textColor = tintColor
            arrowImageView.contentTintColor = tintColor
        } else {
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = Constants.textColor
            iconImageView.contentTintColor = Constants.iconColor
            openDuckAILabel.textColor = NSColor(designSystemColor: .accentTextPrimary)
            arrowImageView.contentTintColor = NSColor(designSystemColor: .accentTextPrimary)
        }

        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isKeyboardNavigating else { return }
        isHovered = true
        onHoverChanged?(true)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        if isKeyboardNavigating {
            onMouseMoved?()
            isKeyboardNavigating = false
        }
        if !isHovered {
            isHovered = true
            onHoverChanged?(true)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isSelected = true
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) {
            onClick?()
        }
        isSelected = false
    }
}
```

- [ ] **Step 4: Add the file to the Xcode project**

Open Xcode and add `AIChatViewAllChatsRowView.swift` to the `DuckDuckGo Privacy Browser` target in the `AIChat/Suggestions` group.

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift
git add macOS/DuckDuckGo/AIChat/Suggestions/AIChatViewAllChatsRowView.swift
git commit -m "Add AIChatViewAllChatsRowView footer row and UserText strings for View all chats"
```

---

## Task 4: Update `AIChatSuggestionsView`

**Files:**
- Modify: `macOS/DuckDuckGo/AIChat/Suggestions/AIChatSuggestionsView.swift`

- [ ] **Step 1: Add the `onViewAllChatsClicked` callback and stored footer view**

In `AIChatSuggestionsView`, add after `onSuggestionDeleted`:

```swift
    var onViewAllChatsClicked: (() -> Void)?
```

Add after `private var viewTrackingArea: NSTrackingArea?`:

```swift
    private var viewAllChatsRowView: AIChatViewAllChatsRowView?
    private var viewAllChatsSeparatorView: NSView?
```

- [ ] **Step 2: Update `calculateHeight` to accept a `showViewAllChats` parameter**

Replace the existing `calculateHeight` signature and body:

```swift
    static func calculateHeight(forSuggestionCount count: Int, showViewAllChats: Bool = false) -> CGFloat {
        guard count > 0 || showViewAllChats else { return 0 }
        let separatorTotalHeight = Constants.separatorHeight + Constants.separatorTopPadding + Constants.separatorBottomPadding
        let rowsHeight = CGFloat(count) * Constants.rowHeight
        let footerHeight: CGFloat = showViewAllChats ? Constants.separatorHeight + Constants.rowHeight : 0
        return separatorTotalHeight + rowsHeight + footerHeight + Constants.bottomPadding
    }
```

- [ ] **Step 3: Add footer row building to `rebuildRows`**

At the end of `rebuildRows(with:)`, after the `separatorView.isHidden` line, add:

```swift
        // Remove existing footer
        viewAllChatsSeparatorView?.removeFromSuperview()
        viewAllChatsSeparatorView = nil
        viewAllChatsRowView?.removeFromSuperview()
        viewAllChatsRowView = nil

        // Append footer row when enabled
        if boundViewModel?.showViewAllChats == true {
            let footerSeparator = NSView()
            footerSeparator.translatesAutoresizingMaskIntoConstraints = false
            footerSeparator.wantsLayer = true
            NSAppearance.withAppAppearance {
                footerSeparator.layer?.backgroundColor = NSColor(designSystemColor: .lines).cgColor
            }
            stackView.addArrangedSubview(footerSeparator)
            footerSeparator.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            footerSeparator.heightAnchor.constraint(equalToConstant: Constants.separatorHeight).isActive = true
            viewAllChatsSeparatorView = footerSeparator

            let footerRow = AIChatViewAllChatsRowView()
            footerRow.translatesAutoresizingMaskIntoConstraints = false
            footerRow.onClick = { [weak self] in self?.onViewAllChatsClicked?() }
            footerRow.onHoverChanged = { [weak self] isHovered in
                if isHovered {
                    // select(at:) guards against out-of-bounds, so use the dedicated method
                    self?.boundViewModel?.selectViewAllChats()
                }
            }
            footerRow.onMouseMoved = { [weak self] in self?.boundViewModel?.acknowledgeMouseMovement() }
            stackView.addArrangedSubview(footerRow)
            footerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            viewAllChatsRowView = footerRow
        }
```

- [ ] **Step 4: Update `updateSelection` to handle the footer row index**

In `updateSelection(_:isKeyboardNavigating:)`, after the `for (index, rowView) in rowViews.enumerated()` loop, add:

```swift
        // Update the "view all" row selection state
        if let footerRow = viewAllChatsRowView {
            let isFooterSelected = (selectedIndex == rowViews.count)
            footerRow.isSelected = isFooterSelected
            footerRow.isKeyboardNavigating = isKeyboardNavigating
            if isKeyboardNavigating {
                footerRow.isHovered = false
            }
        }
```

- [ ] **Step 5: Update `bind(to:onHeightChange:)` to react to `showViewAllChats` changes**

In `bind(to:onHeightChange:)`, add a second subscription after the `viewModel.$filteredSuggestions` subscription:

```swift
        // Rebuild when showViewAllChats toggles (footer row added/removed)
        viewModel.$showViewAllChats
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showViewAllChats in
                guard let self else { return }
                self.rebuildRows(with: viewModel.filteredSuggestions)
                self.updateSelection(viewModel.selectedIndex, isKeyboardNavigating: viewModel.isKeyboardNavigating)
                let newHeight = AIChatSuggestionsView.calculateHeight(
                    forSuggestionCount: viewModel.filteredSuggestions.count,
                    showViewAllChats: showViewAllChats
                )
                onHeightChange(newHeight)
            }
            .store(in: &cancellables)
```

- [ ] **Step 6: Update existing height call in the `filteredSuggestions` subscription**

In the `viewModel.$filteredSuggestions` sink, update the height calculation call:

```swift
                if countChanged {
                    let newHeight = AIChatSuggestionsView.calculateHeight(
                        forSuggestionCount: suggestions.count,
                        showViewAllChats: viewModel.showViewAllChats
                    )
                    onHeightChange(newHeight)
                }
```

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Suggestions/AIChatSuggestionsView.swift
git commit -m "Add View all chats footer row support to AIChatSuggestionsView"
```

---

## Task 5: Update `AIChatOmnibarController`

**Files:**
- Modify: `macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift`

- [ ] **Step 1: Add `isViewAllChatsEnabled` computed property**

After `isOmnibarToolsEnabled`, add:

```swift
    /// Whether the "View all chats" footer row is enabled.
    var isViewAllChatsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatViewAllChatsNativeOmnibar)
    }
```

- [ ] **Step 2: Update `fetchSuggestionsIfNeeded` to over-fetch and set `showViewAllChats`**

Replace the body of the `currentFetchTask` task in `fetchSuggestionsIfNeeded(query:)`:

```swift
        currentFetchTask = Task { [weak self] in
            guard let self else { return }

            let maxChats = self.isViewAllChatsEnabled
                ? reader.maxHistoryCount + 1
                : reader.maxHistoryCount
            let suggestions = await reader.fetchSuggestions(query: query.isEmpty ? nil : query, maxChats: maxChats)

            guard !Task.isCancelled else { return }

            let totalFetched = suggestions.pinned.count + suggestions.recent.count
            self.suggestionsViewModel.showViewAllChats = self.isViewAllChatsEnabled && totalFetched > reader.maxHistoryCount
            self.suggestionsViewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent)
        }
```

- [ ] **Step 3: Add `viewAllChats()` method**

After `submitSelectedSuggestion()`, add:

```swift
    /// Opens a new duck.ai tab. Called when the user clicks or keyboard-selects the "View all chats" footer row.
    func viewAllChats() {
        aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
    }
```

- [ ] **Step 4: Update `submitSelectedSuggestion()` to handle the virtual footer row**

Replace the full `submitSelectedSuggestion()` body:

```swift
    func submitSelectedSuggestion() -> Bool {
        guard isSuggestionsEnabled else { return false }

        if suggestionsViewModel.isViewAllChatsSelected {
            viewAllChats()
            currentText = ""
            return true
        }

        guard let selectedSuggestion = suggestionsViewModel.selectedSuggestion else {
            return false
        }

        delegate?.aiChatOmnibarController(self, didSelectSuggestion: selectedSuggestion)
        currentText = ""
        return true
    }
```

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift
git commit -m "Wire over-fetch detection and viewAllChats action in AIChatOmnibarController"
```

---

## Task 6: Wire `onViewAllChatsClicked`

**Files:**
- Modify: `macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift`

- [ ] **Step 1: Wire `onViewAllChatsClicked` in `AIChatOmnibarContainerViewController`**

In `macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift`, in `setupSuggestionsView()`, add after the `suggestionsView.onSuggestionClicked` block (around line 419):

```swift
        suggestionsView.onViewAllChatsClicked = { [weak self] in
            guard let self else { return }
            self.omnibarController.viewAllChats()
        }
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift
git commit -m "Wire onViewAllChatsClicked in AIChatOmnibarContainerViewController"
```

---

## Verification

- [ ] Build the project — `⌘B` in Xcode — and confirm there are no compile errors.
- [ ] Enable the flag internally: in Xcode, set a breakpoint in `isViewAllChatsEnabled` or temporarily hard-code `return true`, then run.
- [ ] Open the duck.ai address bar with 6+ chats in history. Confirm:
  - "View all chats" footer row appears below the 5 suggestion rows
  - Keyboard navigation (`↓`) advances into the footer row (highlighted with background tint)
  - Pressing `↑` from the footer row goes back to the last suggestion
  - Clicking the footer row opens a new duck.ai tab
  - Pressing `Return` on the footer row opens a new duck.ai tab
- [ ] Open with 5 or fewer chats. Confirm the footer row does not appear.
- [ ] Disable the flag. Confirm the footer row does not appear regardless of chat count.
