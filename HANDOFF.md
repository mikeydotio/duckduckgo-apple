# HANDOFF — Duck.ai OS-level entry point PoC

> ⚠️ **Drop this file before opening a PR.** It exists only to transfer
> state between machines. Cleanup at the bottom.

## What this branch is

PoC for a macOS OS-level Duck.ai entry point (menu-bar icon + global
shortcut + floating omnibar). Branch: `tom/os-level-entry-point-poc`,
based on `main`. Tracked in
[Asana — macOS PoC subtask](https://app.asana.com/1/137249556945/task/1214253504941652)
and
[parent project](https://app.asana.com/1/137249556945/project/1209671977594486/task/1210568591398674).

## Current status

| Milestone | Status |
| --- | --- |
| M1 — Settings toggle (no behavior) | ✅ done |
| M2 — Menu-bar status item, visibility-only | ✅ done |
| M3 — Empty floating panel on click | ✅ done |
| M4 — `AIChatOmnibarController` optional tab model refactor | ✅ done |
| M5 — Real omnibar UI embedded in floating panel (no submit) | ✅ done |
| M6 — Submit hand-off, text-only | ✅ done |
| M7 — Submit hand-off with rich payload (model / mode / reasoning) | ✅ done |
| M8 — Local keyboard shortcut (DDG-foreground only) | ⏭ next |
| M9 — Global shortcut + Accessibility prompt | ⏳ pending |
| M10 — Login-item registration | ⏳ pending |
| M11 — Accessory activation policy on background launch | ⏳ pending |

Each commit on the branch corresponds to one milestone. Build is clean
through M7 and the user has manually verified each milestone's UI.

### Known polish items carried forward

- **First-show hover under the text container**: tracking areas don't
  fire for the cursor's already-inside position the very first time the
  panel comes up. Subsequent shows are fine. A reliable fix would need
  `CGEvent` injection (Accessibility permission required) — out of
  scope for the PoC.
- **Image attachments hidden in the floating panel** (`hidesImageAttachments = true`).
  The attach button presented an `NSOpenPanel` sheet that conflicted
  with the non-activating panel — icon bounce, sheet swallowed the
  panel on dismiss. Attachments will return through a richer
  menu-style entry point in a follow-up.

### Important context for M9 (worth flagging now)

The old hack-days prototype (`origin/tom/hack-days/entry-point`) used a
Carbon `RegisterEventHotKey`-based hot-key library — **no Accessibility
permission required**, unlike `NSEvent.addGlobalMonitorForEvents(.keyDown)`
which does need it. Strong recommendation to either pull in
[soffes/HotKey](https://github.com/soffes/HotKey) or write a ~80-line
in-tree Carbon wrapper for M9 instead of the plan's `NSEvent` approach.
This eliminates the Accessibility prompt entirely.

## Instructions for the new Claude session

1. Make sure you're on this branch:
   ```bash
   git checkout tom/os-level-entry-point-poc
   git pull
   ```
2. **Restore the plan file** to its expected location:
   ```bash
   mkdir -p ~/.claude/plans
   cp HANDOFF.md ~/.claude/plans/we-are-going-to-purrfect-puppy.md
   # then trim the wrapper sections — only the "Original plan" block below
   # is the plan itself
   ```
   (Or copy just the `## Original plan content` section below into that
   file by hand — easier to read than scripting.)
3. Start Claude Code in this repo and open with the following kickoff
   prompt:

   > Continuing the OS-level Duck.ai entry-point PoC. Plan at
   > `~/.claude/plans/we-are-going-to-purrfect-puppy.md`. Branch
   > `tom/os-level-entry-point-poc`, M1 through M7 verified and
   > committed. Read `HANDOFF.md` at the repo root for context and the
   > polish items carried forward, then proceed to M8 (local
   > Ctrl+Alt+Space keyboard shortcut, DDG-foreground only). After M8
   > is verified, drop the HANDOFF commit per its own cleanup
   > instructions before opening a PR.

4. Verify the build before making any new changes:
   ```bash
   xcodebuild -project macOS/DuckDuckGo-macOS.xcodeproj \
              -scheme "macOS Browser" \
              -destination 'platform=macOS' \
              -configuration Debug build
   ```

## Cleanup before PR

This file and the WIP commit that introduced it MUST be dropped before
the branch goes to review:

```bash
# This file is in the most recent commit on the branch.
git log -1 --oneline    # confirm the HEAD is the HANDOFF commit
git reset HEAD~1
rm HANDOFF.md
git status              # should show no diffs
git push --force-with-lease
```

After that, the branch contains only the seven clean M1–M7 commits and
is PR-ready (after M8 and beyond land).

---

## Original plan content

> Copy everything below into
> `~/.claude/plans/we-are-going-to-purrfect-puppy.md` on the new
> machine.

# PoC: macOS OS-level entry point for Duck.ai

## Context

Prototype the macOS slice of [Asana: Desktop Browsers — OS-Level entry point for Duck.ai](https://app.asana.com/1/137249556945/project/1209671977594486/task/1210568591398674) (3-week macOS [parent](https://app.asana.com/1/137249556945/project/1208671677432066/task/1210568491396677), [PoC subtask](https://app.asana.com/1/137249556945/task/1214253504941652)).

Goal: a system-wide Duck.ai entry point — a status bar icon and a global keyboard shortcut that summon a floating omnibar above other apps. Reuse the existing rich Duck.ai address-bar omnibar UI (input, image attachments, tools, suggestions, model picker, reasoning effort) so look and capabilities match what we ship in the address bar today.

User-confirmed scope:
- Status bar item lives **inside the main DuckDuckGo app process** (no helper-agent target).
- Reuse `AIChatOmnibarContainerViewController` by **making `tabCollectionViewModel` optional** in `AIChatOmnibarController`.
- Submit focuses/creates a main browser window and opens a new selected AIChat tab with the query auto-submitted.
- Hardcoded shortcut: **Ctrl+Alt+Space**. Floating window centered horizontally, ~1/3 down from top of `NSScreen.main.visibleFrame`.

Out of scope: onboarding/discoverability dialog, configurable shortcut UI, automated tests, pixel telemetry, helper-agent target, Windows port.

## Approach: 11 incremental milestones

Each milestone is a **standalone, UI-testable change**. We don't move to the next one until the current one passes its verification step. This lets us catch regressions early (especially around the existing address-bar omnibar) and keep diffs reviewable.

All new files live under `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/`.

---

### Milestone 1 — Settings toggle (no behavior)

Add a new preference flag with no functional effect, just storage + UI + persistence.

- [SharedPackages/AIChat/Sources/AIChat/macOS/PublicAPI/AIChatPreferencesStorage.swift](SharedPackages/AIChat/Sources/AIChat/macOS/PublicAPI/AIChatPreferencesStorage.swift) — add `var isGlobalShortcutEnabled: Bool { get set }` + `isGlobalShortcutEnabledPublisher: AnyPublisher<Bool, Never>`. UserDefaults key `aiChat.isGlobalShortcutEnabled`, default `false`.
- [macOS/DuckDuckGo/Preferences/Model/AIChatPreferences.swift](macOS/DuckDuckGo/Preferences/Model/AIChatPreferences.swift) — mirror `@Published var isGlobalShortcutEnabled` and Combine wiring.
- [macOS/DuckDuckGo/Preferences/View/PreferencesAIChat.swift](macOS/DuckDuckGo/Preferences/View/PreferencesAIChat.swift) — new `PreferencePaneSection` "Duck.ai global entry point" with one `ToggleMenuItem` and a placeholder caption.

**Verify**: open Preferences → AI Chat → toggle on/off; quit and relaunch; toggle state persists.

---

### Milestone 2 — Status bar icon, visibility-only

Show the status bar Duck.ai icon when the toggle is on; hide when off. No click behavior yet.

- New: `DuckAIStatusBarController.swift`. `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`, template image (Duck.ai glyph from `DesignResourcesKitIcons`).
- New: `GlobalDuckAIController.swift`, owned by `AppDelegate`, subscribes to `aiChatPreferences.$isGlobalShortcutEnabled` and calls `statusBar.install()` / `uninstall()`.
- Right-click menu: "Open Duck.ai" (no-op for now), "Quit DuckDuckGo" (`NSApp.terminate(nil)`).
- Left-click: no-op for now (logs only).

Pattern reference: [StatusBarMenu.swift](macOS/LocalPackages/NetworkProtectionMac/Sources/NetworkProtectionUI/Menu/StatusBarMenu.swift).

**Verify**: toggle the preference on → icon appears in menu bar; right-click shows menu; toggle off → icon disappears.

---

### Milestone 3 — Empty floating panel on click

Left-clicking the status bar icon (and "Open Duck.ai" menu item) shows a borderless floating panel with placeholder content. Escape closes; click outside closes; click again toggles.

- New: `DuckAIFloatingOmnibarWindow.swift` — `NSPanel` subclass: `[.borderless, .nonactivatingPanel]`, `level = .floating`, `hidesOnDeactivate = true`, `canBecomeKey = true`, transparent background, drop shadow, rounded corners. Override `cancelOperation(_:)` to close.
- New: `DuckAIFloatingOmnibarWindowController.swift` — owns the panel; for now hosts a placeholder `NSView` with a label. Width 580 pt, height ~80 pt.
- Position on every `show()`: `let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame; origin.x = v.midX - width/2; origin.y = v.maxY - v.height/3 - height`.
- `GlobalDuckAIController` wires status bar click → `floatingWindowController.toggle()`.

**Verify**: click status item → empty panel appears in top third of screen; Escape closes; clicking another app dismisses it; click status item again → reappears.

---

### Milestone 4 — Refactor `AIChatOmnibarController` to optional tab model (regression check)

Pure refactor. No new feature exposed. Address-bar Duck.ai must keep working exactly as today.

- [macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift](macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift):
  - `tabCollectionViewModel: TabCollectionViewModel` → optional, default `nil`. Stored property + init param both optional.
  - `subscribeToSelectedTabViewModel()` early-returns when nil.
  - `openNewVoiceChat()` guards `guard let tabCollectionViewModel else { return }`.
  - Existing `sharedTextState?.…` paths (lines 506, 512, 524, 597, 622) and `if let sharedTextState` guard at line 243 already handle nil — keep them.
  - Extract the prompt-building block at lines ~672–690 of `submit()` into `private func makeNativePrompt(for trimmedText: String, images: [...]) -> AIChatNativePrompt` (used in M6+).
- Add new delegate method `aiChatOmnibarController(_:requestsGlobalSubmissionOf prompt: AIChatNativePrompt)` with a default-no-op extension so existing conformers don't need updates.
- In `submit()`, branch on `tabCollectionViewModel == nil` — for now both branches do the existing inline logic (so this milestone is purely the surface refactor, with the global branch never taken yet because no caller passes nil yet).
- Update any test factory of `AIChatOmnibarController` that needs an explicit nil to keep compiling.

**Verify**: full app build passes. Open the browser, switch to Duck.ai mode in the address bar, type, submit, switch tabs and back — per-tab text and tool persistence still works exactly as before. Image attachments + suggestions + model picker still work in the address-bar omnibar.

---

### Milestone 5 — Real omnibar UI in the floating panel (no submit)

Replace the placeholder content with the actual `AIChatOmnibarContainerViewController`. Submit is still wired to the existing `submit()` flow but **without a target window** — pressing Enter just clears the field for now (or no-ops). Goal of this milestone is purely visual fidelity + interaction with tools/attachments/suggestions.

- `DuckAIFloatingOmnibarWindowController` constructs `AIChatOmnibarController(aiChatTabOpener:..., tabCollectionViewModel: nil, ...)` and `AIChatOmnibarContainerViewController(themeManager:..., omnibarController:...)` and embeds the container's view as the panel's content view.
- Subscribe to height-change callbacks (`onSuggestionsHeightChanged`, `onPassthroughHeightNeedsUpdate`) and `setContentSize(_:)` while keeping the top edge anchored.
- The new global-mode delegate method on the floating controller is a stub at this milestone — it just closes the window.
- On `show()`, call `omnibarController.onOmnibarActivated()` and make the text field first responder.

**Verify**: click status item → real Duck.ai omnibar UI appears (input, tools row, attachments, suggestions, model picker). Type a query → suggestions populate and the panel grows. Toggle web search / image generation / reasoning effort → buttons toggle correctly. Drag/paste an image → attachment appears. Press Enter → window closes (no tab opens yet).

---

### Milestone 6 — Submit hand-off, text-only

Pressing Enter focuses/creates a main DDG window and opens a new selected Duck.ai tab with the query auto-submitted.

- In `AIChatOmnibarController.submit()`, when `tabCollectionViewModel == nil`, build the prompt via the extracted `makeNativePrompt` helper (text only at this milestone — pass empty images/no-mode/no-toolChoice/no-reasoning) and call `delegate?.aiChatOmnibarController(self, requestsGlobalSubmissionOf: prompt)`. Then `cleanup()`.
- `DuckAIFloatingOmnibarWindowController` implements the new delegate method:
  1. `let manager = Application.appDelegate.windowControllersManager`.
  2. Find target main window (first non-burner, non-popup) or call existing `WindowControllersManagerProtocol` API to open a new main window.
  3. `targetMainWindow.window?.makeKeyAndOrderFront(nil)`, `NSApp.activate(ignoringOtherApps: true)`.
  4. `Application.appDelegate.aiChatTabOpener.openAIChatTab(with: .query(text, shouldAutoSubmit: true), behavior: .newTab(selected: true))`.
  5. Re-set the prompt via `AIChatPromptHandler.shared.setData(prompt)` (same pattern as the existing inline path).
  6. Close the floating window.

**Verify**: type a plain text query, press Enter → floating window dismisses, browser window comes forward (or a new one opens), new selected tab loads Duck.ai with the query auto-submitted.

---

### Milestone 7 — Submit hand-off with attachments, tools, model, reasoning

Wire the full `makeNativePrompt` payload through the global submission path so image attachments, tool selections (web search / image generation), model picker selection, and reasoning effort all carry over.

- Update the global branch in `AIChatOmnibarController.submit()` to use the same `effectiveModelId / effectiveMode / effectiveToolChoice / effectiveReasoningEffort / nativePromptImages(...)` calls the existing inline path uses, and pass them to `makeNativePrompt`. The pre-async ordering (capture before await) and `waitForAttachmentsReady` await must be identical.

**Verify**:
- Submit with an image attachment → image appears in the resulting Duck.ai chat.
- Toggle web search → submit → web-search mode honored.
- Toggle image generation → submit → image-generation mode honored.
- Pick a different model → submit → chat header shows the picked model.
- Pick a non-default reasoning effort → submit → effort applied.

---

### Milestone 8 — Local keyboard shortcut (DDG-foreground only)

Ctrl+Alt+Space toggles the floating omnibar **when DDG is the foreground app**. Background trigger comes in M9.

- New: `DuckAIGlobalShortcutMonitor.swift` — for now, only `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`.
- Match: `event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .option] && event.keyCode == 0x31` (kVK_Space).
- Return `nil` from the handler when matched (consume the event).
- `GlobalDuckAIController.apply(enabled: true)` now also calls `shortcutMonitor.start()`; off → `stop()`.

**Verify**: with DDG in the foreground (any DDG window key), press Ctrl+Alt+Space → omnibar toggles open/closed. With another app foreground (e.g. Safari), the shortcut does nothing yet.

---

### Milestone 9 — Global shortcut + Accessibility prompt

Add the global monitor so the shortcut works from any app, after the user grants Accessibility permission.

- Add a second monitor in `DuckAIGlobalShortcutMonitor`: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` with the same match logic.
- On first `start()`, call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` to surface the system permission prompt.
- Persist a "we already prompted" bool in `AIChatPreferencesStorage` so we don't re-prompt every launch.
- Update the toggle caption in [PreferencesAIChat.swift](macOS/DuckDuckGo/Preferences/View/PreferencesAIChat.swift) to mention Ctrl+Alt+Space and the Accessibility requirement.

> **Reconsider before implementation**: the old prototype at
> `origin/tom/hack-days/entry-point` used a Carbon `RegisterEventHotKey`-based
> hot-key library that does NOT require Accessibility permission. Strongly
> consider pulling in `soffes/HotKey` or writing a ~80-line in-tree Carbon
> wrapper instead of `NSEvent.addGlobalMonitorForEvents`. Same UX, no system
> prompt for the user.

**Verify**:
- Toggle the preference on → Accessibility prompt appears (first time only). Grant permission, restart DDG.
- With another app foreground (Safari, Notes, Finder) → press Ctrl+Alt+Space → DDG activates and the omnibar appears.
- Submit from there → main browser window comes forward and opens the Duck.ai tab.
- Toggle off → shortcut stops working from background apps; status icon disappears.

---

### Milestone 10 — Login-item registration

Toggling the preference on registers DDG to launch at login. Toggle off unregisters. App still launches as a regular foreground app at this milestone (accessory mode comes in M11).

- [macOS/LocalPackages/LoginItems/Sources/LoginItems/LoginItem.swift](macOS/LocalPackages/LoginItems/Sources/LoginItems/LoginItem.swift): add a backing variant for `SMAppService.mainApp` (e.g. an internal enum `Backing { case helper(id: String); case mainApp }`). `enable() / disable() / status` switch on the backing. Static `LoginItem.mainApp(defaults:logger:)` factory.
- Confirm deployment target is macOS 13+ (verify before implementation). If older OS must be supported, gate with `#available(macOS 13, *)` and no-op the registration on older OS — toggle still wires status item + shortcut.
- `GlobalDuckAIController.apply(enabled: true)` now also calls `loginItem.enable()`; off → `disable()`.

**Verify**: toggle on → System Settings → General → Login Items shows DuckDuckGo. Log out and log back in → DDG launches automatically (still with Dock icon and a normal browser window at this milestone). Toggle off → entry disappears from System Settings; next login does not auto-launch DDG.

---

### Milestone 11 — Accessory activation policy on background launch

When launched as a login item, DDG comes up without a Dock icon and without a browser window — only the status bar icon. As soon as the user shows a browser window (via status-bar submit, dock, Cmd+N, etc.), the Dock icon reappears.

- In `AppDelegate.applicationWillFinishLaunching` (so we set policy before any window factory runs), detect login-launch via the `kAEOpenApplication` Apple Event's `keyAELaunchedAsLogInItem` parameter (`NSAppleEventManager.shared().currentAppleEvent`). If true AND `isGlobalShortcutEnabled`:
  1. `NSApp.setActivationPolicy(.accessory)`.
  2. Skip the normal "open new browser window on launch" path.
- Switch back to `.regular`:
  - In `DuckAIFloatingOmnibarWindowController`'s submission path, just before activating the main window.
  - In the existing `WindowControllersManager` notification of new main window (any other path that opens a browser window).
- Fallback if Apple-Event detection is unreliable on the deployment target: heuristic — "if `isGlobalShortcutEnabled` and no main browser window exists 2 seconds post-launch, switch to `.accessory`". Use this only if the Apple-Event approach proves flaky during M11 implementation.

**Verify**:
- Toggle on, quit DDG, log out, log in → DDG launches without a Dock icon and with no browser window; the menu-bar Duck.ai icon is the only visible UI.
- Click the status item → omnibar appears.
- Submit a query → browser window comes forward, Dock icon appears, new Duck.ai tab loads.
- Quit and re-login → background-launch behavior repeats.
- Toggle off, log out, log in → DDG does not auto-launch.

---

## Critical files (cumulative across milestones)

To create:
- `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/GlobalDuckAIController.swift` (M2)
- `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/DuckAIStatusBarController.swift` (M2)
- `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/DuckAIFloatingOmnibarWindow.swift` (M3)
- `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/DuckAIFloatingOmnibarWindowController.swift` (M3, evolves M5–M7)
- `macOS/DuckDuckGo/AIChat/GlobalEntryPoint/DuckAIGlobalShortcutMonitor.swift` (M8, evolves M9)

To modify:
- [SharedPackages/AIChat/Sources/AIChat/macOS/PublicAPI/AIChatPreferencesStorage.swift](SharedPackages/AIChat/Sources/AIChat/macOS/PublicAPI/AIChatPreferencesStorage.swift) (M1, M9)
- [macOS/DuckDuckGo/Preferences/Model/AIChatPreferences.swift](macOS/DuckDuckGo/Preferences/Model/AIChatPreferences.swift) (M1)
- [macOS/DuckDuckGo/Preferences/View/PreferencesAIChat.swift](macOS/DuckDuckGo/Preferences/View/PreferencesAIChat.swift) (M1, M9)
- [macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift](macOS/DuckDuckGo/AIChat/AIChatOmnibarController.swift) (M4, M6, M7)
- [macOS/LocalPackages/LoginItems/Sources/LoginItems/LoginItem.swift](macOS/LocalPackages/LoginItems/Sources/LoginItems/LoginItem.swift) (M10)
- `macOS/DuckDuckGo/Application/AppDelegate.swift` (M2 instantiation, M11 activation policy)
- Any test factory of `AIChatOmnibarController` that needs the optional parameter to keep compiling (M4)

## Risks / gotchas

- **`AIChatOmnibarContainerViewController` reparenting**: container draws clip mask + shadow tuned for the address bar (constants `clipMaskBottomOffset: 14`, `shadowOverlapHeight: 11`). M5 verifies visual; if seams look wrong, the lightest fix is to set the panel's own background/shadow and zero the container's shadow inset.
- **`.nonactivatingPanel` + `canBecomeKey`**: finicky combo. If the text field can't take focus in M3/M5, drop `.nonactivatingPanel` and accept brief app activation on show.
- **Activation policy timing (M11)**: must be set before window factory runs in `applicationWillFinishLaunching`; setting it later leaves stale menu-bar state.
- **`SMAppService.mainApp` requires macOS 13+**: confirm deployment target before M10. Gate appropriately if older OS is supported.
- **`cleanup()` after global submit**: shared state is nil so cleanup is a pure local reset — safe. Verify in M6 that the `currentText = ""` in `submit()` (line 697) and the new global-branch ordering don't fire suggestion fetches after teardown.
- **Burner windows**: M6 submit hand-off must not land in a burner main window — filter `mainWindowControllers`.
- **Voice mode in global omnibar**: voice button is wired into the address-bar omnibar; in global mode `openNewVoiceChat` no-ops because `tabCollectionViewModel` is nil. Either hide the voice button when controller is in global mode (M5) or accept the no-op for the PoC.
- **Accessibility permission UX (M9)**: macOS shows a list-and-relaunch flow; the toggle caption must mention this clearly.
- **Re-prompt avoidance (M9)**: persist the "already prompted" flag so that a second toggle-off → toggle-on cycle doesn't re-trigger the system dialog.
