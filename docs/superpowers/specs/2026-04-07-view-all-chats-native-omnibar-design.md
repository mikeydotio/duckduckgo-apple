# View All Chats — Native Address Bar Omnibar

**Date:** 2026-04-07  
**Feature flag:** `aiChatViewAllChatsNativeOmnibar`  
**Branch:** `juan/view-all-chats-ntp` (extend existing branch)

---

## Overview

When the user has more AI chats than the display cap (5), a "View all chats" footer row appears at the bottom of the recent-chats suggestions list in the duck.ai address bar omnibar. Clicking or keyboard-selecting it opens a new duck.ai tab.

The detection strategy mirrors the NTP implementation: fetch `maxHistoryCount + 1` chats; if the result exceeds `maxHistoryCount`, there are more chats than can be shown and the row is revealed.

---

## Feature Flag

### `PrivacyFeature.swift` — `AIChatSubfeature`

```swift
/// Enables "View all chats" row at the bottom of AI chat suggestions in the address bar
case viewAllChatsNativeOmnibar
```

### `FeatureFlag.swift`

```swift
case aiChatViewAllChatsNativeOmnibar

// config:
case .aiChatViewAllChatsNativeOmnibar:
    Config(defaultValue: .internalOnly,
           source: .remoteReleasable(.subfeature(AIChatSubfeature.viewAllChatsNativeOmnibar)),
           category: .duckAI)
```

Starts `internalOnly`, matching `aiChatRemoveSuggestion` precedent.

---

## ViewModel (`AIChatSuggestionsViewModel`)

Location: `SharedPackages/AIChat/Sources/AIChat/Shared/Suggestions/AIChatSuggestionsViewModel.swift`

### New published property

```swift
@Published public var showViewAllChats: Bool = false
```

### New computed property

```swift
/// True when the "view all" virtual row is selected (index one past the last suggestion).
public var isViewAllChatsSelected: Bool {
    showViewAllChats && selectedIndex == filteredSuggestions.count
}
```

### `selectNext()` update

Allow selection to advance one step beyond the last suggestion when `showViewAllChats` is true:

```swift
if nextIndex < filteredSuggestions.count {
    selectedIndex = nextIndex
    return true
} else if showViewAllChats && nextIndex == filteredSuggestions.count {
    selectedIndex = nextIndex   // virtual "view all" row
    return true
}
return false
```

### `clearAllChats()` update

Reset `showViewAllChats = false` alongside the existing reset.

### `setChats()` / `removeSuggestion()` updates

Re-clamp `selectedIndex` to account for the virtual row when `showViewAllChats` is true, so selection stays valid after a deletion.

### `selectedSuggestion` — no change

Returns `nil` for the "view all" index. Callers use `isViewAllChatsSelected` to distinguish this case.

---

## View Layer

### New file: `AIChatViewAllChatsRowView.swift`

Location: `macOS/DuckDuckGo/AIChat/Suggestions/`

An `NSView` subclass (32pt height, same as `AIChatSuggestionRowView`) with:

**Left side:**
- List/lines icon (matching the screenshot)
- "View all chats" label (`UserText.aiChatViewAllChats`)

**Right side (always anchored to trailing edge):**
- `KeyboardShortcutView` configured with `["↑", "↓"]`
- "Open Duck.ai" label (`UserText.aiChatOpenDuckAI`) — semibold, 11pt, matching `chatWithAIAttributedString` style
- Arrow indicator (`NSImageView`)

**Visual states:**
- `isSelected`, `isHovered`, `isKeyboardNavigating` — same appearance logic as `AIChatSuggestionRowView`
- `isHighlighted` forwarded to `KeyboardShortcutView` on selection change

**Callbacks:**
- `var onClick: (() -> Void)?`
- `var onHoverChanged: ((Bool) -> Void)?`
- `var onMouseMoved: (() -> Void)?`

### `AIChatSuggestionsView` changes

**New callback:**
```swift
var onViewAllChatsClicked: (() -> Void)?
```

**New stored view:**
```swift
private var viewAllChatsRowView: AIChatViewAllChatsRowView?
```

**`rebuildRows(with:)` update:**
After building suggestion rows, append the footer when `boundViewModel?.showViewAllChats == true`:
- A thin horizontal separator (same `NSColor(designSystemColor: .lines)` color)
- An `AIChatViewAllChatsRowView` wired to `onViewAllChatsClicked`, `onHoverChanged`, and `onMouseMoved`

**`calculateHeight(forSuggestionCount:showViewAllChats:)` update:**
Add `rowHeight + separatorHeight` when `showViewAllChats` is true. The existing call sites pass the ViewModel's published value.

**`updateSelection(_:isKeyboardNavigating:)` update:**
When `selectedIndex == filteredSuggestions.count`, set selected state on `viewAllChatsRowView` instead of a suggestion row.

**`bind(to:onHeightChange:)` update:**
Add a subscription to `viewModel.$showViewAllChats` that triggers a rebuild and height recalculation when it changes.

---

## Controller (`AIChatOmnibarController`)

Location: `macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift`

### New computed property

```swift
var isViewAllChatsEnabled: Bool {
    featureFlagger.isFeatureOn(.aiChatViewAllChatsNativeOmnibar)
}
```

### `fetchSuggestionsIfNeeded(query:)` update

When the flag is on, request one extra chat to detect overflow:

```swift
let maxChats = isViewAllChatsEnabled ? reader.maxHistoryCount + 1 : reader.maxHistoryCount
let suggestions = await reader.fetchSuggestions(query: ..., maxChats: maxChats)

guard !Task.isCancelled else { return }

let totalFetched = suggestions.pinned.count + suggestions.recent.count
suggestionsViewModel.showViewAllChats = isViewAllChatsEnabled && totalFetched > reader.maxHistoryCount
suggestionsViewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent)
```

`setChats` trims to `maxSuggestions` so the extra chat is never shown — only used for detection.

### New `viewAllChats()` method

```swift
func viewAllChats() {
    aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
}
```

### `submitSelectedSuggestion()` update

Check for the "view all" virtual row before the normal suggestion path:

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

### `cleanup()` update

No explicit change needed — `cleanup()` already calls `suggestionsViewModel.clearAllChats()`, and `clearAllChats()` will reset `showViewAllChats = false` as part of its update.

---

## Wiring (`AIChatOmnibarContainerViewController`)

In `setupSuggestionsView()`, alongside the existing `onSuggestionClicked` wiring:

```swift
suggestionsView.onViewAllChatsClicked = { [weak self] in
    self?.omnibarController.viewAllChats()
}
```

No delegate change needed — `viewAllChats()` calls `aiChatTabOpener` directly, same pattern as `submit()`.

---

## Localization (`UserText.swift`)

```swift
static let aiChatViewAllChats = NSLocalizedString(
    "aichat.suggestions.view-all-chats",
    value: "View all chats",
    comment: "Footer row in the duck.ai address bar suggestions list, opens full chat history"
)

static let aiChatOpenDuckAI = NSLocalizedString(
    "aichat.suggestions.open-duck-ai",
    value: "Open Duck.ai",
    comment: "Label on the 'View all chats' footer row indicating it opens duck.ai"
)
```

---

## Files Changed

| File | Change |
|------|--------|
| `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift` | Add `viewAllChatsNativeOmnibar` to `AIChatSubfeature` |
| `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift` | Add `aiChatViewAllChatsNativeOmnibar` case + config |
| `SharedPackages/AIChat/Sources/AIChat/Shared/Suggestions/AIChatSuggestionsViewModel.swift` | Add `showViewAllChats`, `isViewAllChatsSelected`, update keyboard nav |
| `macOS/DuckDuckGo/AIChat/Suggestions/AIChatViewAllChatsRowView.swift` | **New file** — footer row view |
| `macOS/DuckDuckGo/AIChat/Suggestions/AIChatSuggestionsView.swift` | Add footer row support, `onViewAllChatsClicked`, height update |
| `macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift` | Over-fetch logic, `showViewAllChats` update, `viewAllChats()`, submit guard |
| `macOS/DuckDuckGo/AIChat/AIChatOmnibarContainerViewController.swift` | Wire `onViewAllChatsClicked` |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` | Add `aiChatViewAllChats`, `aiChatOpenDuckAI` |

---

## Out of Scope

- Pixel events for "View all chats" click (can be added as a follow-up)
- Unit tests (separate pass per team convention)
