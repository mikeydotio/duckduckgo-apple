# Duck.ai Floating Launcher Design Spec

## Goal

A ⌘K-invocable floating launcher panel that lets users start new Duck.ai chats (text, voice, image) or resume past ones — with results opening in a standalone floating chat window, independent of the browser's tab model.

## Architecture

Two new surfaces, each a separate window:

1. **AIChatLauncherPanel** — a non-activating NSPanel centered on screen (Spotlight-style). Keyboard-driven. Dismissed after selection.
2. **AIChatStandaloneFloatingWindow** — a new lightweight NSWindow hosting a WKWebView pointed at duck.ai. Not tab-backed. Persists after the launcher dismisses. One instance per `MainWindowController`.

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
│  📌 My ongoing research notes    Pinned │
├─────────────────────────────────────────┤
│ ↑↓ navigate   ↵ open   esc dismiss      │  ← keyboard hint footer
└─────────────────────────────────────────┘
```

Width: ~340 pt. Max visible chat rows: 6 (scrollable if more).

### Behaviour

**Open:** ⌘K shortcut OR toolbar button click. Panel appears centered in the browser window. A dim overlay (`NSColor.black` at 30% opacity) is placed over the browser window's content view (not full-screen). It fades in (0.15s) when the launcher opens and fades out (0.15s) when the launcher dismisses, regardless of dismiss trigger. The search field is cleared and given first responder on every open — previous search text is never retained across open/close cycles.

**Search:** Typing filters chat rows in real-time (title substring match, case-insensitive). The "RECENT" section label is hidden during search. Quick actions remain visible and unaffected. The list scrolls to the top whenever the filter text changes. Filtered results are sorted by timestamp descending (same as unfiltered) — pin status does not override sort order in search results. The pin badge is not shown on rows in search results (only shown in the unfiltered RECENT list).

**Keyboard navigation:**
- Search field has focus on open. Nothing in the chat list is pre-selected.
- ↓ from the search field moves focus to the first chat row. If there are no chat rows (loading or empty state), ↓ does nothing — focus stays in the search field.
- ↑↓ navigate between chat rows once in the list. ↑ from the first row moves focus back to the search field.
- Tab moves focus: search field → quick-action row → first chat row (if any). Shift+Tab reverses.
- Within the quick-action row, Tab/Shift+Tab cycles between the four buttons. ↑↓ does not navigate within the row.
- A focused quick-action button is activated with Space or ↵.
- ↵ on a focused chat row opens it in the standalone floating window, then dismisses the launcher.

**Dismiss:** Esc, ⌘K (while open), clicking outside the panel, selecting a chat row, or activating any quick-action button except Settings. Settings dismisses the launcher and then opens the preferences pane. All dismiss paths behave identically — no animation difference.

**Loading state:** While chat data is being fetched, a `ProgressView` (spinner) is shown in the chat list area in place of rows. The "RECENT" label is hidden. Quick actions are immediately interactive — the user does not wait for history to use them.

**Empty state:** If the fetch succeeds but returns no chats (or if the user has no history), the chat list area shows "No past chats yet" in secondary text. The "RECENT" label is hidden.

**Error/failure state:** If the fetch fails for any reason, treat it identically to the empty state — show "No past chats yet." No error message is shown to the user.

### Quick actions

| Button | Action |
|--------|--------|
| New Chat | Opens standalone floating window at `AIChatRemoteSettings().aiChatURL` |
| Voice | Opens standalone floating window with `?mode=voice` |
| Image | Opens standalone floating window with `?mode=image` |
| Settings | Opens AI Chat preferences pane via `Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .aiChat)`; dismisses launcher |

### Implementation details

- `AIChatLauncherPanel: NSPanel` — activating panel (no `.nonactivatingPanel`). When it opens it becomes the key window (like macOS Spotlight). The browser window remains the main window. This is required for keyboard navigation — arrow keys, Tab, Space, Return all work because the panel owns key focus.
- SwiftUI content via `NSHostingController<AIChatLauncherView>`.
- `AIChatLauncherViewModel: ObservableObject` — holds `searchText`, `filteredChats: [AIChatSuggestion]`, `isLoading: Bool`.
- `filteredChats` is derived: when `searchText` is empty, all fetched chats; otherwise, chats whose title contains `searchText` (case-insensitive).
- Chat data fetched from `AIChatSuggestionsReader` — this type already exists in the codebase and is used by the history sidebar. Interface: `func fetchSuggestions(query: String?) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion])`. Fetch starts when the panel opens. Results are merged pinned + recent, sorted by timestamp descending — no separate "PINNED" section, no special ordering for pins. Pinned chats appear in timestamp order among all chats, distinguished only by the `DesignSystemImages.Glyphs.Size16.pin` icon on their row (same treatment as the history sidebar's `ChatRow`).
- `AIChatLauncherCoordinator` owns the panel, handles open/close/toggle, wires toolbar button and ⌘K, bridges selection events to `AIChatStandaloneFloatingWindowCoordinator`.
- The ⌘K local event monitor is registered and unregistered with the browser window's key status (active only while the browser window is key). This is implemented via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` on the browser window.
- The ⌘K shortcut is not currently assigned in this codebase — no conflict.

---

## Component 2: AIChatStandaloneFloatingWindow

### Purpose

A persistent, resizable NSWindow hosting a single `WKWebView` that loads duck.ai. It is not a browser tab — it has no `Tab` object, no `TabViewModel`, no sidebar. It is a direct web view pointed at duck.ai.

### Visual layout

```
┌──────────────────────────────────┐
│ ● ○ □   🦆 Duck.ai              │  ← transparent title bar, traffic lights
├──────────────────────────────────┤
│                                  │
│         duck.ai web content      │
│                                  │
│                                  │
└──────────────────────────────────┘
```

Default size: 400×600 pt. Min size: 320×480 pt. Frame persisted to UserDefaults under key `"aiChatStandaloneFloatingWindowFrame"` (store as `NSStringFromRect`, restore with `NSRectFromString`).

### Behaviour

- **First open:** window appears centered on the same screen as the parent browser window (no persisted frame yet), at the default 400×600 pt size. WKWebView loads the target URL.
- **Already open + new selection from launcher:** bring the window to front and navigate to the new URL. If the selected URL is identical to the one already loaded, bring the window to front only — do not reload.

- **Closing:** clicking the red traffic light OR pressing ⌘W hides the window (sets `isHidden = true`; not deallocated). Subsequent launcher selections bring it back and navigate it.
- **Re-open:** `AIChatStandaloneFloatingWindowCoordinator.open(url:)` brings the window to front and calls `webView.load(URLRequest(url:))`.
- **Ownership:** one floating window per browser window. Each browser window (`MainWindowController` + its `MainViewController`) is a 1:1 relationship — one `MainViewController` per `MainWindowController`. The floating window coordinator is owned by `MainViewController`. When the parent browser window closes, the coordinator is deallocated, which releases the `NSWindowController` and `WKWebView`. Any in-progress WKWebView load is cancelled by WKWebView dealloc — standard WKWebView teardown.
- **Multiple browser windows:** each browser window has its own floating window. All instances share `WKWebsiteDataStore.default()`, so the duck.ai session (login state) is shared. The windows are navigated independently — opening a chat in one does not affect the other.
- **When floating window is key:** ⌘K is monitored only on the browser window. If the user gives focus to the floating window, ⌘K is not active.
- **Key window transitions:** when the launcher opens, it becomes the key window (expected — it took focus). Auto-dismiss triggers when a window OTHER than the launcher becomes key (another app, the floating window, etc.). On dismiss, the panel dismisses FIRST (synchronously), then the navigation call to the floating window is made. This avoids a race where the floating window stealing key status triggers an auto-dismiss loop.

### Implementation details

- `AIChatStandaloneFloatingWindow: NSWindow` — transparent title bar, traffic lights preserved, `isMovableByWindowBackground = true`. Mirrors the configuration of the existing `AIChatFloatingWindow`.
- `AIChatStandaloneFloatingWindowController: NSWindowController` — owns the window and the `WKWebView`. Exposes:
  ```swift
  func open(url: URL)   // brings to front and navigates
  func hide()           // hides but retains window
  ```
- `WKWebView` configured with a new `WKWebViewConfiguration` using `WKWebsiteDataStore.default()` (so duck.ai session cookies match the browser's duck.ai tabs) and a new `WKProcessPool()` (standalone; no process sharing with browser tabs is required).
- `AIChatStandaloneFloatingWindowCoordinator` — held by `MainViewController`. Owns the controller instance (lazy creation on first use). Builds URLs from `AIChatRemoteSettings`.

---

## URL Building

Uses the same helpers as the history sidebar coordinator:

| Action | URL |
|--------|-----|
| New Chat | `AIChatRemoteSettings().aiChatURL` (base URL, no extra params) |
| Voice | Base URL + `?mode=voice` |
| Image | Base URL + `?mode=image` |
| Existing chat | Base URL + `?chatID=<chatId>` (parameter name confirmed from `AIChatTabOpener.buildChatURL`) |

URL construction is **always against the base URL**, never against the webview's current URL. Build a fresh `URLComponents` from `AIChatRemoteSettings().aiChatURL` for every navigation. Remove any existing `mode` or `chatID` query items, then append the new one as needed.

---

## Toolbar button

- **Position:** in `navigationButtons`, immediately after `aiChatHistoryButton`. Insertion: `navigationButtons.insertArrangedSubview(launcherButton, at: index(of: aiChatHistoryButton) + 1)`. If `aiChatHistoryButton` is absent, fall back to inserting immediately before `goBackButton` (same fallback the history button uses: `firstIndex(of: goBackButton) ?? 0`). Resulting order: `… | aiChatHistoryButton | aiChatLauncherButton | goBackButton | …`
- **Icon:** `DesignSystemImages.Glyphs.Size16.aiChat`
- **Active state:** highlighted **only when the launcher panel is open**. The button is NOT highlighted when only the standalone floating window is visible. Clicking always toggles the launcher.
- **Accessibility label:** "Duck.ai Launcher"

---

## Keyboard shortcut

- **⌘K** — toggles the launcher panel (open if closed, close if open).
- Registered as a local `NSEvent` monitor in `AIChatLauncherCoordinator`, active only when the browser window is key.
- ⌘K is not currently assigned anywhere in this codebase — no conflict.

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
2. Creates `AIChatLauncherCoordinator` with reference to the floating coordinator and `AIChatSuggestionsReader`
3. Registers ⌘K local event monitor
4. Wires toolbar button active state binding
5. Sets `onAIChatLauncherButtonClicked` closure on `NavigationBarViewController`

---

## Mutual exclusion

- Opening the launcher does **not** close the history sidebar or the AI Chat sidebar. It is a transient overlay.
- If the standalone floating window is already open when the launcher opens, the floating window stays visible in the background.

---

## Out of scope

- System-wide ⌘K shortcut (works outside the browser) — deferred
- Syncing floating window chat state back to the history sidebar list — deferred
- Typing a query in the launcher search field and submitting it as a new chat prompt (search only filters history; it does not create chats from the launcher input)
- Pinning/unpinning chats from the launcher
