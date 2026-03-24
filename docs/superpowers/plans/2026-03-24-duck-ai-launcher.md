# Duck.ai Floating Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a ⌘K-invocable floating launcher panel that opens Duck.ai chats (new, voice, image, or existing) in a standalone floating window detached from the browser's tab model.

**Architecture:** Two new surfaces — `AIChatLauncherPanel` (activating NSPanel, Spotlight-style, keyboard-driven) and `AIChatStandaloneFloatingWindow` (NSWindow + WKWebView pointing directly at duck.ai, not tab-backed). The launcher is wired to a new toolbar button and a ⌘K local event monitor in `MainViewController`. Results always open in the standalone floating window.

**Tech Stack:** Swift, AppKit, SwiftUI (`NSHostingController`), Combine, WebKit (`WKWebView`)

**Spec:** `docs/superpowers/specs/2026-03-24-duck-ai-launcher.md`

---

## File Map

**New files — create these:**

| Path | Responsibility |
|------|---------------|
| `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindow.swift` | NSWindow subclass: transparent titlebar, traffic lights, window configuration |
| `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindowController.swift` | NSWindowController: owns WKWebView, exposes `open(url:)` / `hide()`, persists frame |
| `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindowCoordinator.swift` | Owned by MainViewController: lazy creation, URL building, delegates to controller |
| `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherViewModel.swift` | ObservableObject: searchText, filteredChats, selectedIndex, action closures |
| `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherView.swift` | SwiftUI view: search input, quick-action buttons, chat list, footer hints |
| `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherPanel.swift` | NSPanel subclass: activating, intercepts ↑↓↵Esc via keyDown override |
| `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherCoordinator.swift` | Core logic: open/close/toggle, dim overlay, ⌘K monitor, bridges to floating window |
| `macOS/DuckDuckGo/MainWindow/MainViewController+AIChatLauncher.swift` | `setupAIChatLauncher()` extension wiring everything together |

**Modified files:**

| Path | Change |
|------|--------|
| `macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift` | Add launcher toolbar button (pattern mirrors `aiChatHistoryButton`) |
| `macOS/DuckDuckGo/MainWindow/MainViewController.swift` | Add stored properties, call `setupAIChatLauncher()` in `viewDidLoad` |
| `macOS/DuckDuckGo/Common/Localizables/UserText.swift` | Add 8 `aiChatLauncher*` strings |
| `macOS/DuckDuckGo/Localization/Localizable.xcstrings` | Add 8 corresponding `ai.chat.launcher.*` keys |
| `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj` | Register all 8 new Swift files in both targets |

---

## Task 1: AIChatStandaloneFloatingWindow + Controller

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindow.swift`
- Create: `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindowController.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow
```

- [ ] **Step 2: Create `AIChatStandaloneFloatingWindow.swift`**

```swift
//
//  AIChatStandaloneFloatingWindow.swift
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

/// A lightweight NSWindow subclass for displaying duck.ai as a standalone floating surface,
/// independent of the browser's tab model.
final class AIChatStandaloneFloatingWindow: NSWindow {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        animationBehavior = .documentWindow
        collectionBehavior = [.fullScreenNone]
        minSize = NSSize(width: 320, height: 480)
    }
}
```

- [ ] **Step 3: Create `AIChatStandaloneFloatingWindowController.swift`**

```swift
//
//  AIChatStandaloneFloatingWindowController.swift
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
import WebKit

/// Owns the standalone floating duck.ai window and its WKWebView.
/// Not tab-backed — navigates duck.ai directly via URL.
final class AIChatStandaloneFloatingWindowController: NSWindowController {

    // MARK: - Constants

    private enum Constants {
        static let defaultSize = NSSize(width: 400, height: 600)
        static let frameUserDefaultsKey = "aiChatStandaloneFloatingWindowFrame"
    }

    // MARK: - Private

    private let webView: WKWebView
    private var currentURL: URL?

    // MARK: - Init

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.processPool = WKProcessPool()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        self.webView = wv

        let initialRect = NSRect(origin: .zero, size: Constants.defaultSize)
        let floatingWindow = AIChatStandaloneFloatingWindow(contentRect: initialRect)

        super.init(window: floatingWindow)

        let contentVC = NSViewController()
        contentVC.view = NSView()
        contentVC.view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: contentVC.view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: contentVC.view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: contentVC.view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: contentVC.view.bottomAnchor),
        ])
        floatingWindow.contentViewController = contentVC
        floatingWindow.delegate = self

        restoreFrameOrCenter()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public API

    /// Brings the window to front and navigates to the given URL.
    /// If the URL is already loaded, only brings the window to front.
    func open(url: URL) {
        if window?.isVisible == false {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
        if url.absoluteString != currentURL?.absoluteString {
            currentURL = url
            webView.load(URLRequest(url: url))
        }
    }

    /// Hides the window without deallocating it. Frame is persisted.
    func hide() {
        persistFrame()
        window?.orderOut(nil)
    }

    // MARK: - Frame Persistence

    private func restoreFrameOrCenter() {
        if let stored = UserDefaults.standard.string(forKey: Constants.frameUserDefaultsKey) {
            let rect = NSRectFromString(stored)
            if rect != .zero {
                window?.setFrame(rect, display: false)
                return
            }
        }
        window?.center()
    }

    private func persistFrame() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Constants.frameUserDefaultsKey)
    }
}

// MARK: - NSWindowDelegate

extension AIChatStandaloneFloatingWindowController: NSWindowDelegate {

    /// Intercept close (traffic light + ⌘W): hide instead of destroy.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        persistFrame()
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/
git commit -m "feat: add AIChatStandaloneFloatingWindow and Controller"
```

---

## Task 2: AIChatStandaloneFloatingWindowCoordinator

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindowCoordinator.swift`

- [ ] **Step 1: Create `AIChatStandaloneFloatingWindowCoordinator.swift`**

```swift
//
//  AIChatStandaloneFloatingWindowCoordinator.swift
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

import AIChat
import AppKit

/// Owned by MainViewController. Lazily creates the standalone floating window
/// and builds duck.ai URLs for launcher selections.
@MainActor
final class AIChatStandaloneFloatingWindowCoordinator {

    private lazy var windowController = AIChatStandaloneFloatingWindowController()

    // MARK: - Public API

    func open(url: URL) {
        windowController.open(url: url)
    }

    func openNewChat() {
        open(url: baseURL())
    }

    func openVoiceChat() {
        open(url: buildModeURL(mode: AIChatURLParameters.voiceModeValue))
    }

    func openImageChat() {
        open(url: buildModeURL(mode: AIChatURLParameters.imageModeValue))
    }

    func openExistingChat(chatId: String) {
        open(url: buildChatURL(chatId: chatId))
    }

    // MARK: - URL Building

    private func baseURL() -> URL {
        AIChatRemoteSettings().aiChatURL
    }

    private func buildModeURL(mode: String) -> URL {
        let settings = AIChatRemoteSettings()
        guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return settings.aiChatURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == AIChatURLParameters.modeName || $0.name == "chatID" }
        queryItems.append(URLQueryItem(name: AIChatURLParameters.modeName, value: mode))
        components.queryItems = queryItems
        return components.url ?? settings.aiChatURL
    }

    private func buildChatURL(chatId: String) -> URL {
        let settings = AIChatRemoteSettings()
        guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return settings.aiChatURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == AIChatURLParameters.modeName || $0.name == "chatID" }
        queryItems.append(URLQueryItem(name: "chatID", value: chatId))
        components.queryItems = queryItems
        return components.url ?? settings.aiChatURL
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/StandaloneFloatingWindow/AIChatStandaloneFloatingWindowCoordinator.swift
git commit -m "feat: add AIChatStandaloneFloatingWindowCoordinator"
```

---

## Task 3: AIChatLauncherViewModel

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherViewModel.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p macOS/DuckDuckGo/AIChat/Launcher
```

- [ ] **Step 2: Create `AIChatLauncherViewModel.swift`**

```swift
//
//  AIChatLauncherViewModel.swift
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

import AIChat
import Combine

/// Data model for the launcher panel. Logic lives in AIChatLauncherCoordinator.
@MainActor
final class AIChatLauncherViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchText: String = "" {
        didSet {
            // Reset selection when the filter changes
            selectedIndex = nil
        }
    }

    @Published private(set) var allChats: [AIChatSuggestion] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var selectedIndex: Int? = nil

    // MARK: - Derived

    var filteredChats: [AIChatSuggestion] {
        guard !searchText.isEmpty else { return allChats }
        return allChats.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Action Closures (wired by coordinator)

    var onNewChat: (() -> Void)?
    var onNewVoiceChat: (() -> Void)?
    var onNewImageChat: (() -> Void)?
    var onSettings: (() -> Void)?
    var onChatSelected: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Updates

    func update(chats: [AIChatSuggestion], isLoading: Bool) {
        self.allChats = chats
        self.isLoading = isLoading
        self.selectedIndex = nil
    }

    func reset() {
        searchText = ""
        selectedIndex = nil
    }

    // MARK: - Keyboard Navigation

    func moveSelectionDown() {
        let items = filteredChats
        guard !items.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = min(current + 1, items.count - 1)
        } else {
            selectedIndex = 0
        }
    }

    func moveSelectionUp() {
        guard let current = selectedIndex else { return }
        if current == 0 {
            selectedIndex = nil  // return focus to search field
        } else {
            selectedIndex = current - 1
        }
    }

    func activateSelection() {
        guard let index = selectedIndex, index < filteredChats.count else { return }
        let chat = filteredChats[index]
        onChatSelected?(chat.chatId)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherViewModel.swift
git commit -m "feat: add AIChatLauncherViewModel"
```

---

## Task 4: AIChatLauncherView

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherView.swift`

**Important context:**
- Follow the hover-state pattern from `AIChatHistorySidebarView.swift` — use `@State private var isHovered` + `.onHover { isHovered = $0 }` + `Color.controlsFillPrimary` background.
- Import `DesignResourcesKitIcons` for icon access.
- Use `Color(designSystemColor: .surfacePrimary)` for background (matches nav toolbar).
- Icon names used in the history sidebar (already confirmed working): `DesignSystemImages.Glyphs.Size16.aiChatAdd`, `.permissionMicrophone`, `.image`, `.aiChatSettings`, `.pin`.

- [ ] **Step 1: Create `AIChatLauncherView.swift`**

```swift
//
//  AIChatLauncherView.swift
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

import AIChat
import AppKit
import DesignResourcesKitIcons
import SwiftUI

struct AIChatLauncherView: View {

    @ObservedObject var viewModel: AIChatLauncherViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider()
            quickActionsRow
            Divider()
            chatListContent
            Divider()
            footerRow
        }
        .background(Color(designSystemColor: .surfacePrimary))
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Search Row

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.aiChat)
                .renderingMode(.template)
                .foregroundColor(.primary)
                .frame(width: 16, height: 16)
            TextField(UserText.aiChatLauncherSearchPlaceholder, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { viewModel.activateSelection() }
            Text("⌘K")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 6) {
            QuickActionButton(
                title: UserText.aiChatLauncherNewChat,
                nsImage: DesignSystemImages.Glyphs.Size16.aiChatAdd,
                action: { viewModel.onNewChat?() }
            )
            QuickActionButton(
                title: UserText.aiChatLauncherVoice,
                nsImage: DesignSystemImages.Glyphs.Size16.permissionMicrophone,
                action: { viewModel.onNewVoiceChat?() }
            )
            QuickActionButton(
                title: UserText.aiChatLauncherImage,
                nsImage: DesignSystemImages.Glyphs.Size16.image,
                action: { viewModel.onNewImageChat?() }
            )
            QuickActionButton(
                title: UserText.aiChatLauncherSettings,
                nsImage: DesignSystemImages.Glyphs.Size16.aiChatSettings,
                action: { viewModel.onSettings?() }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Chat List

    @ViewBuilder
    private var chatListContent: some View {
        if viewModel.isLoading && viewModel.allChats.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.filteredChats.isEmpty {
            Text(UserText.aiChatLauncherNoChats)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .multilineTextAlignment(.center)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if viewModel.searchText.isEmpty {
                            Text(UserText.aiChatLauncherRecentHeader)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(Array(viewModel.filteredChats.enumerated()), id: \.element.chatId) { index, chat in
                            LauncherChatRow(
                                suggestion: chat,
                                isSelected: viewModel.selectedIndex == index,
                                onSelected: { viewModel.onChatSelected?(chat.chatId) }
                            )
                            .id(index)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .onChange(of: viewModel.selectedIndex) { newIndex in
                    if let idx = newIndex {
                        withAnimation { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack(spacing: 12) {
            Text("↑↓ navigate")
            Text("↵ open")
            Text("esc dismiss")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - QuickActionButton

private struct QuickActionButton: View {
    let title: String
    let nsImage: NSImage
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: nsImage)
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovered ? Color.controlsFillPrimary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - LauncherChatRow

private struct LauncherChatRow: View {
    let suggestion: AIChatSuggestion
    let isSelected: Bool
    let onSelected: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelected) {
            HStack(spacing: 8) {
                Text(suggestion.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if suggestion.isPinned {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.pin)
                        .renderingMode(.template)
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                }
                if let timestamp = suggestion.timestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.controlsFillPrimary.opacity(1.5) : (isHovered ? Color.controlsFillPrimary : Color.clear))
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherView.swift
git commit -m "feat: add AIChatLauncherView (SwiftUI)"
```

---

## Task 5: AIChatLauncherPanel

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherPanel.swift`

**Important context:** This is an activating NSPanel (no `.nonactivatingPanel` in style mask). When shown it becomes key, enabling full keyboard navigation. Arrow keys (↑↓) and Esc are intercepted in `keyDown` and forwarded to the viewModel. ↵ (Return) is handled by SwiftUI's `.onSubmit` in the TextField; it bubbles up to `keyDown` only if no SwiftUI control consumes it.

- [ ] **Step 1: Create `AIChatLauncherPanel.swift`**

```swift
//
//  AIChatLauncherPanel.swift
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
import SwiftUI

/// Activating NSPanel that hosts AIChatLauncherView.
/// Intercepts arrow keys and Esc for keyboard navigation.
final class AIChatLauncherPanel: NSPanel {

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let escape: UInt16 = 53
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    private enum Constants {
        static let panelSize = NSSize(width: 340, height: 420)
    }

    private var hostingController: NSHostingController<AIChatLauncherView>!
    let viewModel: AIChatLauncherViewModel

    init(viewModel: AIChatLauncherViewModel) {
        self.viewModel = viewModel
        super.init(
            contentRect: NSRect(origin: .zero, size: Constants.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = false
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false

        hostingController = NSHostingController(rootView: AIChatLauncherView(viewModel: viewModel))
        contentViewController = hostingController
    }

    // MARK: - Keyboard Interception

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.downArrow:
            viewModel.moveSelectionDown()
        case KeyCode.upArrow:
            viewModel.moveSelectionUp()
        case KeyCode.returnKey:
            // Only fires if SwiftUI's .onSubmit didn't consume the event
            viewModel.activateSelection()
        case KeyCode.escape:
            viewModel.onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - ⌘W: hide via dismiss

    override func performClose(_ sender: Any?) {
        viewModel.onDismiss?()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherPanel.swift
git commit -m "feat: add AIChatLauncherPanel (NSPanel with keyboard interception)"
```

---

## Task 6: AIChatLauncherCoordinator

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherCoordinator.swift`

**Important context:**
- The coordinator is the brain. It owns the panel, the dim overlay, and the ⌘K local event monitor.
- Dim overlay: an `NSView` added to the browser window's `contentView` as a subview, `NSColor.black` at 30% alpha, fades in/out over 0.15s.
- `windowDidResignKey` notification on the panel triggers auto-dismiss (user clicked outside or switched apps).
- The dismiss sequence is: (1) call `closeLauncher()` synchronously, (2) then open the floating window. This avoids a race where the floating window stealing key status triggers a dismiss loop.
- Reuse the `buildModeURL` / `buildChatURL` pattern from `AIChatHistorySidebarCoordinator` verbatim.

- [ ] **Step 1: Create `AIChatLauncherCoordinator.swift`**

```swift
//
//  AIChatLauncherCoordinator.swift
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

import AIChat
import AppKit
import Combine

@MainActor
final class AIChatLauncherCoordinator: ObservableObject {

    // MARK: - Public State

    @Published private(set) var isLauncherOpen: Bool = false

    // MARK: - Dependencies

    private let floatingWindowCoordinator: AIChatStandaloneFloatingWindowCoordinator
    private let suggestionsReader: AIChatSuggestionsReading

    // MARK: - Private State

    private let viewModel = AIChatLauncherViewModel()
    private lazy var panel = AIChatLauncherPanel(viewModel: viewModel)

    private weak var parentWindow: NSWindow?
    private var dimView: NSView?
    private var keyEventMonitor: Any?
    private var fetchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        floatingWindowCoordinator: AIChatStandaloneFloatingWindowCoordinator,
        suggestionsReader: AIChatSuggestionsReading
    ) {
        self.floatingWindowCoordinator = floatingWindowCoordinator
        self.suggestionsReader = suggestionsReader
        wireClosures()
    }

    // MARK: - Public API

    func toggleLauncher(from window: NSWindow) {
        if isLauncherOpen {
            closeLauncher()
        } else {
            openLauncher(from: window)
        }
    }

    func closeLauncher() {
        guard isLauncherOpen else { return }
        isLauncherOpen = false
        fetchTask?.cancel()
        fetchTask = nil
        unregisterResignKeyObserver()
        unregisterKeyMonitor()
        panel.orderOut(nil)
        removeDimOverlay()
        viewModel.reset()
    }

    /// Call when the parent browser window closes to release resources.
    func tearDown() {
        closeLauncher()
        suggestionsReader.tearDown()
    }

    // MARK: - Private: Open

    private func openLauncher(from window: NSWindow) {
        parentWindow = window
        isLauncherOpen = true
        viewModel.update(chats: [], isLoading: true)

        centerPanel(in: window)
        addDimOverlay(to: window)
        panel.makeKeyAndOrderFront(nil)

        registerResignKeyObserver()
        registerKeyMonitor()

        fetchTask = Task { [weak self] in
            await self?.fetchAndPublish()
        }
    }

    // MARK: - Private: Panel Positioning

    private func centerPanel(in window: NSWindow) {
        let panelSize = panel.frame.size
        let windowFrame = window.frame
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        var x = windowFrame.midX - panelSize.width / 2
        var y = windowFrame.midY - panelSize.height / 2
        x = max(screenFrame.minX, min(x, screenFrame.maxX - panelSize.width))
        y = max(screenFrame.minY, min(y, screenFrame.maxY - panelSize.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Private: Dim Overlay

    private func addDimOverlay(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let view = NSView(frame: contentView.bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        view.alphaValue = 0
        contentView.addSubview(view, positioned: .above, relativeTo: nil)
        dimView = view
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            view.animator().alphaValue = 1
        }
    }

    private func removeDimOverlay() {
        guard let dim = dimView else { return }
        dimView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            dim.animator().alphaValue = 0
        }, completionHandler: {
            dim.removeFromSuperview()
        })
    }

    // MARK: - Private: Event Monitor (⌘K)

    private func registerKeyMonitor() {
        unregisterKeyMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // ⌘K while launcher is open: close it
            if event.charactersIgnoringModifiers == "k" &&
               event.modifierFlags.contains(.command) {
                self.closeLauncher()
                return nil
            }
            return event
        }
    }

    private func unregisterKeyMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Private: Auto-Dismiss on Resign Key

    private func registerResignKeyObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    private func unregisterResignKeyObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    @objc private func panelDidResignKey() {
        closeLauncher()
    }

    // MARK: - Private: Chat Fetch

    private func fetchAndPublish() async {
        let result = await suggestionsReader.fetchSuggestions(query: nil)
        guard !Task.isCancelled else { return }
        let all = (result.pinned + result.recent).sorted {
            ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }
        viewModel.update(chats: all, isLoading: false)
    }

    // MARK: - Private: Closure Wiring

    private func wireClosures() {
        viewModel.onNewChat = { [weak self] in
            guard let self else { return }
            closeLauncher()
            floatingWindowCoordinator.openNewChat()
        }

        viewModel.onNewVoiceChat = { [weak self] in
            guard let self else { return }
            closeLauncher()
            floatingWindowCoordinator.openVoiceChat()
        }

        viewModel.onNewImageChat = { [weak self] in
            guard let self else { return }
            closeLauncher()
            floatingWindowCoordinator.openImageChat()
        }

        viewModel.onSettings = { [weak self] in
            self?.closeLauncher()
            Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .aiChat)
        }

        viewModel.onChatSelected = { [weak self] chatId in
            guard let self else { return }
            closeLauncher()
            floatingWindowCoordinator.openExistingChat(chatId: chatId)
        }

        viewModel.onDismiss = { [weak self] in
            self?.closeLauncher()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Launcher/AIChatLauncherCoordinator.swift
git commit -m "feat: add AIChatLauncherCoordinator"
```

---

## Task 7: NavigationBar Toolbar Button

**Files:**
- Modify: `macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift`

**Context:** Follow the exact pattern of `aiChatHistoryButton` (lines 170–183) and `setupAIChatHistoryButton()` (lines 1204–1222). The launcher button is inserted at `index(of: aiChatHistoryButton) + 1`. If `aiChatHistoryButton` is absent, fall back to `firstIndex(of: goBackButton) ?? 0`.

Read the file first, then make these changes:

- [ ] **Step 1: Add `onAIChatLauncherButtonClicked` property**

After the existing `var onAIChatHistoryButtonClicked: (() -> Void)?` line, add:

```swift
var onAIChatLauncherButtonClicked: (() -> Void)?
```

- [ ] **Step 2: Add the `aiChatLauncherButton` lazy var**

After the closing `}()` of the `aiChatHistoryButton` lazy var, add:

```swift
private lazy var aiChatLauncherButton: MouseOverButton = {
    let button = MouseOverButton(frame: .zero)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.image = .aiChat
    button.imageScaling = .scaleProportionallyDown
    button.bezelStyle = .shadowlessSquare
    button.isBordered = false
    button.sendAction(on: .leftMouseDown)
    button.target = self
    button.action = #selector(aiChatLauncherButtonAction(_:))
    button.setAccessibilityIdentifier("NavigationBarViewController.aiChatLauncherButton")
    button.toolTip = UserText.aiChatLauncherButtonTooltip
    return button
}()
```

- [ ] **Step 3: Add `setupAIChatLauncherButton()` and `updateAIChatLauncherButtonState(isActive:)` and action**

After the closing `}` of `setupAIChatHistoryButton()`, add:

```swift
private func setupAIChatLauncherButton() {
    if aiChatLauncherButton.superview == nil {
        let insertIndex: Int
        if let historyIdx = navigationButtons.arrangedSubviews.firstIndex(of: aiChatHistoryButton) {
            insertIndex = historyIdx + 1
        } else {
            insertIndex = navigationButtons.arrangedSubviews.firstIndex(of: goBackButton) ?? 0
        }
        navigationButtons.insertArrangedSubview(aiChatLauncherButton, at: insertIndex)

        let size = theme.addressBarStyleProvider.addressBarButtonSize
        NSLayoutConstraint.activate([
            aiChatLauncherButton.widthAnchor.constraint(equalToConstant: size),
            aiChatLauncherButton.heightAnchor.constraint(equalToConstant: size)
        ])
    }

    let colorsProvider = theme.colorsProvider
    aiChatLauncherButton.normalTintColor = colorsProvider.iconsColor
    aiChatLauncherButton.mouseOverColor = colorsProvider.buttonMouseOverColor
    aiChatLauncherButton.mouseDownColor = colorsProvider.buttonMouseDownColor
}

func updateAIChatLauncherButtonState(isActive: Bool) {
    aiChatLauncherButton.isHighlighted = isActive
}

@IBAction private func aiChatLauncherButtonAction(_ sender: NSButton) {
    onAIChatLauncherButtonClicked?()
}
```

- [ ] **Step 4: Call `setupAIChatLauncherButton()` from the theme update method**

Find the call to `setupAIChatHistoryButton()` in the theme/appearance update method (search for `setupAIChatHistoryButton()`). Add `setupAIChatLauncherButton()` directly after it.

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift
git commit -m "feat: add Duck.ai launcher toolbar button to NavigationBarViewController"
```

---

## Task 8: MainViewController Wiring

**Files:**
- Modify: `macOS/DuckDuckGo/MainWindow/MainViewController.swift`
- Create: `macOS/DuckDuckGo/MainWindow/MainViewController+AIChatLauncher.swift`

**Context:** Follow the exact pattern of `aiChatHistorySidebarCoordinator` / `historySidebarCancellables` (lines 77–78) and `MainViewController+AIChatHistorySidebar.swift`.

- [ ] **Step 1: Add stored properties to `MainViewController.swift`**

After `var historySidebarCancellables = Set<AnyCancellable>()`, add:

```swift
var aiChatLauncherCoordinator: AIChatLauncherCoordinator?
var standaloneFloatingWindowCoordinator: AIChatStandaloneFloatingWindowCoordinator?
var launcherCancellables = Set<AnyCancellable>()
var launcherKeyMonitor: Any?
```

- [ ] **Step 2: Call `setupAIChatLauncher()` in `viewDidLoad`**

After the `setupAIChatHistorySidebar()` call (line ~354), add:

```swift
setupAIChatLauncher()
```

- [ ] **Step 3: Create `MainViewController+AIChatLauncher.swift`**

```swift
//
//  MainViewController+AIChatLauncher.swift
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

import AIChat
import AppKit
import Combine
import Foundation

extension MainViewController {

    /// Creates the Duck.ai launcher and standalone floating window and wires them up.
    /// Call once from viewDidLoad, after setupAIChatHistorySidebar().
    func setupAIChatLauncher() {
        let privacyConfig = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager
        let suggestionsReader = AIChatSuggestionsReader(
            suggestionsReader: SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfig),
            historySettings: AIChatHistorySettings(privacyConfig: privacyConfig)
        )

        standaloneFloatingWindowCoordinator = AIChatStandaloneFloatingWindowCoordinator()

        aiChatLauncherCoordinator = AIChatLauncherCoordinator(
            floatingWindowCoordinator: standaloneFloatingWindowCoordinator!,
            suggestionsReader: suggestionsReader
        )

        // Bind toolbar button active state
        aiChatLauncherCoordinator?.$isLauncherOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen in
                self?.navigationBarViewController.updateAIChatLauncherButtonState(isActive: isOpen)
            }
            .store(in: &launcherCancellables)

        // Wire toolbar button closure
        navigationBarViewController.onAIChatLauncherButtonClicked = { [weak self] in
            guard let self, let window = view.window else { return }
            aiChatLauncherCoordinator?.toggleLauncher(from: window)
        }

        // Register ⌘K local event monitor. Stored in launcherKeyMonitor so it can be
        // explicitly removed when the window closes (NSEvent monitors must be removed manually).
        launcherKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.charactersIgnoringModifiers == "k",
                  event.modifierFlags.contains(.command) else { return event }
            // Only open if launcher is closed and this browser window is key
            guard view.window?.isKeyWindow == true,
                  aiChatLauncherCoordinator?.isLauncherOpen == false else { return event }
            guard let window = view.window else { return event }
            aiChatLauncherCoordinator?.toggleLauncher(from: window)
            return nil
        }

        // Tear down when the browser window closes to avoid a dangling event monitor
        // and to release the suggestions reader.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closingWindow = notification.object as? NSWindow,
                  closingWindow === view.window else { return }
            aiChatLauncherCoordinator?.tearDown()
            if let monitor = launcherKeyMonitor {
                NSEvent.removeMonitor(monitor)
                launcherKeyMonitor = nil
            }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/MainWindow/MainViewController.swift \
        macOS/DuckDuckGo/MainWindow/MainViewController+AIChatLauncher.swift
git commit -m "feat: wire AIChatLauncher in MainViewController"
```

---

## Task 9: UserText + Localizable Strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift`
- Modify: `macOS/DuckDuckGo/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add strings to `UserText.swift`**

After the `// MARK: - AI Chat History Sidebar` block (after line ~1789), add:

```swift
// MARK: - AI Chat Launcher

static let aiChatLauncherSearchPlaceholder = NSLocalizedString(
    "ai.chat.launcher.search.placeholder",
    value: "Ask something or find a chat…",
    comment: "Placeholder text in the Duck.ai launcher panel search field"
)
static let aiChatLauncherNewChat = NSLocalizedString(
    "ai.chat.launcher.new.chat",
    value: "New Chat",
    comment: "Quick action button label for starting a new Duck.ai chat from the launcher"
)
static let aiChatLauncherVoice = NSLocalizedString(
    "ai.chat.launcher.voice",
    value: "Voice",
    comment: "Quick action button label for starting a new Duck.ai voice chat from the launcher"
)
static let aiChatLauncherImage = NSLocalizedString(
    "ai.chat.launcher.image",
    value: "Image",
    comment: "Quick action button label for starting a new Duck.ai image chat from the launcher"
)
static let aiChatLauncherSettings = NSLocalizedString(
    "ai.chat.launcher.settings",
    value: "Settings",
    comment: "Quick action button label for opening Duck.ai settings from the launcher"
)
static let aiChatLauncherNoChats = NSLocalizedString(
    "ai.chat.launcher.no.chats",
    value: "No past chats yet",
    comment: "Empty state message in the Duck.ai launcher when there are no past chats"
)
static let aiChatLauncherRecentHeader = NSLocalizedString(
    "ai.chat.launcher.recent.header",
    value: "Recent",
    comment: "Section header above the recent chats list in the Duck.ai launcher panel"
)
static let aiChatLauncherButtonTooltip = NSLocalizedString(
    "ai.chat.launcher.button.tooltip",
    value: "Duck.ai Launcher",
    comment: "Tooltip for the Duck.ai launcher toolbar button"
)
```

- [ ] **Step 2: Add entries to `Localizable.xcstrings`**

Inside the top-level `"strings"` dictionary (alphabetically, after the `ai.chat.history.*` block), add these 8 entries following the exact same JSON structure as the history sidebar keys:

```json
"ai.chat.launcher.button.tooltip" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Duck.ai Launcher"
      }
    }
  }
},
"ai.chat.launcher.image" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Image"
      }
    }
  }
},
"ai.chat.launcher.new.chat" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "New Chat"
      }
    }
  }
},
"ai.chat.launcher.no.chats" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "No past chats yet"
      }
    }
  }
},
"ai.chat.launcher.recent.header" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Recent"
      }
    }
  }
},
"ai.chat.launcher.search.placeholder" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Ask something or find a chat…"
      }
    }
  }
},
"ai.chat.launcher.settings" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Settings"
      }
    }
  }
},
"ai.chat.launcher.voice" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Voice"
      }
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift \
        macOS/DuckDuckGo/Localization/Localizable.xcstrings
git commit -m "feat: add UserText and Localizable strings for Duck.ai launcher"
```

---

## Task 10: Register New Files in project.pbxproj

**Files:**
- Modify: `macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj`

**Context:** The project has two targets: `DuckDuckGo` and `DuckDuckGoTests`. New Swift files need entries in both `PBXBuildFile` (2× each file), `PBXFileReference` (1× each file), and `PBXSourcesBuildPhase` (2× each file). New directories need `PBXGroup` entries. Follow the exact pattern from Task 10 of the history sidebar implementation — find the history sidebar group (UUID `1E4EDA262DE9ED1C0019B6E8`) as a reference for the AIChat group structure.

The 8 new files:

| File | Group |
|------|-------|
| `AIChatStandaloneFloatingWindow.swift` | New group: `AIChat/StandaloneFloatingWindow` |
| `AIChatStandaloneFloatingWindowController.swift` | Same new group |
| `AIChatStandaloneFloatingWindowCoordinator.swift` | Same new group |
| `AIChatLauncherViewModel.swift` | New group: `AIChat/Launcher` |
| `AIChatLauncherView.swift` | Same new group |
| `AIChatLauncherPanel.swift` | Same new group |
| `AIChatLauncherCoordinator.swift` | Same new group |
| `MainViewController+AIChatLauncher.swift` | Existing `MainWindow` group (UUID `AA585DB02490E6FA00E9A3E2`) |

- [ ] **Step 1: Generate UUIDs**

Run this to generate 40 unique UUIDs (you'll need ~34):

```bash
python3 -c "import uuid; [print(str(uuid.uuid4()).upper().replace('-','')[:24]) for _ in range(40)]"
```

Assign them as follows (one UUID per role, per file):

| Role | Count |
|------|-------|
| PBXFileReference (one per file) | 8 |
| PBXBuildFile for DuckDuckGo target (one per file) | 8 |
| PBXBuildFile for DuckDuckGoTests target (one per file) | 8 |
| PBXGroup for StandaloneFloatingWindow | 1 |
| PBXGroup for Launcher | 1 |
| Total | 26 |

- [ ] **Step 2: Add PBXFileReference entries**

In the `/* Begin PBXFileReference section */` block, add one entry per new file (use the pattern from existing sidebar files):

```
XXXXXXXXXXXXXXXXXXXXXXXX /* AIChatStandaloneFloatingWindow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AIChatStandaloneFloatingWindow.swift; sourceTree = "<group>"; };
```

Repeat for all 8 files.

- [ ] **Step 3: Add PBXBuildFile entries**

In the `/* Begin PBXBuildFile section */` block, add two entries per file (one for each target):

```
YYYYYYYYYYYYYYYYYYYYYYYY /* AIChatStandaloneFloatingWindow.swift in Sources */ = {isa = PBXBuildFile; fileRef = XXXXXXXXXXXXXXXXXXXXXXXX /* AIChatStandaloneFloatingWindow.swift */; };
ZZZZZZZZZZZZZZZZZZZZZZZZ /* AIChatStandaloneFloatingWindow.swift in Sources */ = {isa = PBXBuildFile; fileRef = XXXXXXXXXXXXXXXXXXXXXXXX /* AIChatStandaloneFloatingWindow.swift */; };
```

- [ ] **Step 4: Add new PBXGroup entries for Launcher and StandaloneFloatingWindow**

Find the `Sidebar` group inside the `AIChat` group (UUID `1E4EDA262DE9ED1C0019B6E8`). Add two sibling groups immediately after the Sidebar group:

```
LLLLLLLLLLLLLLLLLLLLLLLL /* Launcher */ = {
    isa = PBXGroup;
    children = (
        AAAA /* AIChatLauncherViewModel.swift */,
        BBBB /* AIChatLauncherView.swift */,
        CCCC /* AIChatLauncherPanel.swift */,
        DDDD /* AIChatLauncherCoordinator.swift */,
    );
    path = Launcher;
    sourceTree = "<group>";
};
SSSSSSSSSSSSSSSSSSSSSSSS /* StandaloneFloatingWindow */ = {
    isa = PBXGroup;
    children = (
        EEEE /* AIChatStandaloneFloatingWindow.swift */,
        FFFF /* AIChatStandaloneFloatingWindowController.swift */,
        GGGG /* AIChatStandaloneFloatingWindowCoordinator.swift */,
    );
    path = StandaloneFloatingWindow;
    sourceTree = "<group>";
};
```

Add `LLLLLLLLLLLLLLLLLLLLLLLL` and `SSSSSSSSSSSSSSSSSSSSSSSS` as children of the AIChat parent group.

- [ ] **Step 5: Add `MainViewController+AIChatLauncher.swift` to the MainWindow group**

Find the `MainWindow` group (UUID `AA585DB02490E6FA00E9A3E2`) and add the file reference UUID to its `children` array.

- [ ] **Step 6: Add all 8 files to both target Sources build phases**

Find the `Sources` build phase for `DuckDuckGo` target and add the 8 `PBXBuildFile` UUIDs (first-target set). Do the same for `DuckDuckGoTests` target (second-target set).

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "chore: register Duck.ai launcher and standalone floating window files in Xcode project"
```

---

## Completion

After all 10 tasks are committed, build the project in Xcode to verify there are no compile errors. The expected result:

- A new toolbar button appears left of the back button in the navigation bar
- Pressing ⌘K opens a centered launcher panel with a search field, 4 quick-action buttons, and the recent chats list
- Selecting any item opens/navigates the standalone floating duck.ai window
- Esc, ⌘K, or clicking outside dismisses the launcher
- The floating window hides (not quits) when the red traffic light or ⌘W is used
