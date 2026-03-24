# Duck.ai Floating Launcher Design Spec

## Goal

A ⌘K-invocable floating launcher panel that lets users start new Duck.ai chats (text, voice, image) or resume past ones — with results opening in a standalone floating chat window, independent of the browser's tab model.

## Architecture

Two new surfaces, each a separate window:

1. **AIChatLauncherPanel** — a non-activating NSPanel centered on screen (Spotlight-style). Keyboard-driven. Dismissed after selection.
2. **AIChatStandaloneFloatingWindow** — a new lightweight NSWindow hosting a WKWebView pointed at duck.ai. Not tab-backed. Persists after the launcher dismisses. One instance per browser window (or global singleton — see below).

The existing per-tab `AIChatFloatingWindow` / `AIChatFloatingWindowController` is **not reused**. That infrastructure is tightly coupled to `Tab`, `TabIdentifier`, and `AIChatViewController`. The standalone window is a clean-room design.

---

## Component 1: AIChatLauncherPanel

### Visual layout (top → bottom)

```
┌─────────────────────────────────────────┐
│ 🦆  Ask something or find a chat…   ⌘K │  ← search input row
├─────────────────────────────────────────┤
│  💬 New Chat   🎙 Voice   🖼 Image   ⚙️  │  ← quick-action row (4 buttons)
├─────────────────────────────────────────┤
│ RECENT                                  │
│  💬 Plan a trip to Japan        2h ago  │  ← chat rows (scrollable)
│  💬 Explain quantum computing  yesterday│
│  💬 Fix my Swift concurrency bug  3d ago│
│  📌 My ongoing research notes    Pinned │
├─────────────────────────────────────────┤
│ ↑↓ navigate   ↵ open   esc dismiss      │  ← keyboard hint footer
└─────────────────────────────────────────┘
```

Width: ~340 pt. Max visible chat rows: 6 (scrollable if more).

### Behaviour

- **Open**: ⌘K shortcut OR toolbar button click. Panel appears centered in the browser window, backdrop dims slightly.
- **Search**: Typing filters chat rows in real-time (title substring match). Filtered view hides the "RECENT" label and shows matching rows only.
- **Navigation**: ↑↓ arrow keys move selection highlight through rows. Quick-action buttons are also keyboard-reachable (Tab to move between sections).
- **Confirm**: ↵ or click opens the selected item in the standalone floating window, then dismisses the launcher.
- **Dismiss**: Esc, clicking outside the panel, or selecting an item.
- **Empty state**: If no chats exist, hide the RECENT section and show "No past chats yet" in muted text.

### Quick actions

| Button | Action |
|--------|--------|
| New Chat | Opens standalone window with a fresh duck.ai session |
| Voice | Opens standalone window with `?mode=voice` |
| Image | Opens standalone window with `?mode=image` |
| Settings | Opens AI Chat preferences pane; dismisses launcher |

### Implementation details

- `AIChatLauncherPanel: NSPanel` — `NSWindowStyleMask.nonactivatingPanel`. Does not steal key focus from the browser.
- SwiftUI content via `NSHostingController<AIChatLauncherView>`.
- `AIChatLauncherViewModel: ObservableObject` — holds `searchText`, `filteredChats`, loading state.
- Chat data fetched from `AIChatSuggestionsReader` (same as history sidebar) when the panel opens.
- `AIChatLauncherCoordinator` owns the panel, handles open/close/toggle, wires toolbar button and ⌘K, bridges selection events to `AIChatStandaloneFloatingWindowCoordinator`.
- Toolbar button: added to `navigationButtons` in `NavigationBarViewController`, before the existing history sidebar button. Active state reflects `isSidebarOpen`.

---

## Component 2: AIChatStandaloneFloatingWindow

### Purpose

A persistent, resizable NSWindow hosting a single `WKWebView` that loads duck.ai. It is not a browser tab — it has no `Tab` object, no `TabViewModel`, no sidebar. It is a direct web view pointed at duck.ai.

### Visual layout

```
┌──────────────────────────────────┐
│ ● ○ □   🦆 Duck.ai              │  ← native title bar (transparent, traffic lights)
├──────────────────────────────────┤
│                                  │
│         duck.ai web content      │
│                                  │
│                                  │
└──────────────────────────────────┘
```

Default size: 400×600 pt. Min size: 320×480 pt. Frame persisted to UserDefaults.

### Behaviour

- **First open**: window appears, WKWebView loads the target URL.
- **Already open + new selection from launcher**: navigates the existing WKWebView to the new URL (no new window).
- **Closing**: user clicks the red traffic light. Window is hidden (not deallocated) for fast re-open.
- **Re-open**: launcher selection calls `show()` on the existing coordinator, which brings the window forward and navigates.
- **Ownership**: one instance per `MainWindowController` (not global, not per-tab). If the browser window closes, the floating window closes with it.

### Implementation details

- `AIChatStandaloneFloatingWindow: NSWindow` — mirrors `AIChatFloatingWindow` configuration: transparent title bar, traffic lights preserved, `isMovableByWindowBackground = true`.
- `AIChatStandaloneFloatingWindowController: NSWindowController` — owns the window and the `WKWebView`. Exposes:
  ```swift
  func navigate(to url: URL)
  func show()
  func hide()
  ```
- `WKWebView` uses the shared `WKProcessPool` and `WKWebsiteDataStore` from the browser (so duck.ai session cookies are shared — the user is already logged in).
- `AIChatStandaloneFloatingWindowCoordinator` — held by `MainViewController`. Owns the controller instance, builds URLs from `AIChatRemoteSettings`, handles lazy creation.

---

## URL Building

Reuses existing helpers:

- New chat: `AIChatRemoteSettings().aiChatURL`
- Voice: append `?mode=voice`
- Image: append `?mode=image`
- Existing chat: `?chat=<chatId>` (verify parameter name against duck.ai's actual scheme)

---

## Wiring in MainViewController

```swift
// New stored properties
var aiChatLauncherCoordinator: AIChatLauncherCoordinator?
var standaloneFloatingWindowCoordinator: AIChatStandaloneFloatingWindowCoordinator?
var launcherCancellables = Set<AnyCancellable>()
```

`setupAIChatLauncher()` — called from `viewDidLoad`, after `setupAIChatHistorySidebar()`:
1. Creates `AIChatStandaloneFloatingWindowCoordinator`
2. Creates `AIChatLauncherCoordinator` with a reference to the floating coordinator
3. Registers ⌘K shortcut
4. Wires toolbar button

---

## Toolbar button

- Position: in `navigationButtons`, immediately after the existing history sidebar button (left nav area)
- Icon: `DesignSystemImages.Glyphs.Size16.aiChat` (same as AI Chat)
- Active state: highlighted when the launcher is open OR when the standalone floating window is visible
- Accessibility label: "Duck.ai Launcher"

---

## Keyboard shortcut

- **⌘K** — toggles the launcher panel
- Registered via `NSApp.mainMenu` or a local event monitor in `AIChatLauncherCoordinator`
- Only active when the browser window is key

---

## Mutual exclusion

- Opening the launcher does **not** close the history sidebar or the AI Chat sidebar.
- The launcher is a transient overlay; it doesn't conflict with persistent panels.
- If the standalone floating window is open when the launcher opens, the floating window stays visible in the background.

---

## Out of scope

- System-wide shortcut (works outside the browser) — deferred
- Syncing floating window chat state back to the history sidebar — deferred
- Sharing `WKWebView` session across multiple browser windows — out of scope; each browser window has its own standalone floating window
- Pinning/unpinning chats from the launcher — out of scope
