# Duck.ai Chat History Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native left-side browser sidebar that shows Duck.ai chat history, toggled by a new toolbar button left of the back/forward buttons.

**Architecture:** A new `AIChatHistorySidebarCoordinator` (owned by `MainViewController`) drives a left-side container in `BrowserTabViewController` via the `AIChatHistorySidebarHosting` protocol — mirroring how the right-side AI Chat sidebar works. A SwiftUI view hosted in an `NSHostingController` renders the list; an `ObservableObject` view model bridges coordinator and view.

**Tech Stack:** Swift, AppKit + SwiftUI, Combine, `AIChatSuggestionsReading` (existing), `AIChatTabOpening` (existing), `DesignSystemImages` icons (existing)

**Spec:** `docs/superpowers/specs/2026-03-24-duck-ai-history-sidebar-design.md`

---

> **Architecture note on hosting:** The spec says `AIChatHistorySidebarHosting` abstracts `MainViewController`. In practice it abstracts `BrowserTabViewController`, which owns the web content layout — the same pattern used by `AIChatSidebarHosting` for the right sidebar. The coordinator still lives on `MainViewController`.

---

### Task 1: Localization strings

**Files:**
- Modify: `macOS/DuckDuckGo/Common/Localizables/UserText.swift` (near other `aiChat*` strings)
- Modify: `macOS/DuckDuckGo/Localization/Localizable.xcstrings`

- [ ] **Step 1: Add strings to UserText.swift**

Find the existing `aiChat*` string block (search for `aiChatHistoryNewChat`) and add the following new strings in the same `// MARK: - AI Chat History Sidebar` block:

```swift
// MARK: - AI Chat History Sidebar
static let aiChatHistorySidebarTitle = NSLocalizedString(
    "ai.chat.history.sidebar.title",
    value: "Duck.ai",
    comment: "Title shown in the header of the Duck.ai chat history sidebar"
)
static let aiChatHistorySidebarNewChat = NSLocalizedString(
    "ai.chat.history.sidebar.new.chat",
    value: "New Chat",
    comment: "Button label for starting a new Duck.ai chat from the history sidebar"
)
static let aiChatHistorySidebarNewVoiceChat = NSLocalizedString(
    "ai.chat.history.sidebar.new.voice.chat",
    value: "New Voice Chat",
    comment: "Button label for starting a new Duck.ai voice chat from the history sidebar"
)
static let aiChatHistorySidebarNewImage = NSLocalizedString(
    "ai.chat.history.sidebar.new.image",
    value: "New Image",
    comment: "Button label for starting a new Duck.ai image chat from the history sidebar"
)
static let aiChatHistorySidebarChatsHeader = NSLocalizedString(
    "ai.chat.history.sidebar.chats.header",
    value: "Chats",
    comment: "Section header label above the chat list in the history sidebar"
)
static let aiChatHistorySidebarNoChats = NSLocalizedString(
    "ai.chat.history.sidebar.no.chats",
    value: "No recent chats",
    comment: "Empty state message when there are no Duck.ai chats in the history sidebar"
)
static let aiChatHistorySidebarSettingsAndMore = NSLocalizedString(
    "ai.chat.history.sidebar.settings.and.more",
    value: "Settings & More",
    comment: "Footer button label for opening Duck.ai settings from the history sidebar"
)
```

- [ ] **Step 2: Add entries to Localizable.xcstrings**

Open `macOS/DuckDuckGo/Localization/Localizable.xcstrings` and add one entry per key. Use the same format as existing entries. Example entry structure:

```json
"ai.chat.history.sidebar.title" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Duck.ai"
      }
    }
  }
},
```

Add all 7 keys with their English values.

- [ ] **Step 3: Build to confirm no errors**

Use Xcode MCP `BuildProject` or build via Xcode. Expect: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/Common/Localizables/UserText.swift
git add macOS/DuckDuckGo/Localization/Localizable.xcstrings
git commit -m "feat: add localization strings for Duck.ai history sidebar"
```

---

### Task 2: AIChatHistorySidebarViewModel

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarViewModel.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  AIChatHistorySidebarViewModel.swift
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

/// Pure data carrier for the Duck.ai chat history sidebar.
/// All business logic is in AIChatHistorySidebarCoordinator.
@MainActor
final class AIChatHistorySidebarViewModel: ObservableObject {

    @Published private(set) var chats: [AIChatSuggestion] = []
    @Published private(set) var isLoading: Bool = false

    // Set by coordinator before the view is shown
    var onChatSelected: ((String) -> Void)?     // receives chatId
    var onNewChat: (() -> Void)?
    var onNewVoiceChat: (() -> Void)?
    var onNewImageChat: (() -> Void)?
    var onSettings: (() -> Void)?
    var onClose: (() -> Void)?

    func update(chats: [AIChatSuggestion], isLoading: Bool) {
        self.chats = chats
        self.isLoading = isLoading
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Use `mcp__xcode__XcodeWrite` to write the file, which registers it automatically — or add it manually via Xcode's "Add Files" → target `DuckDuckGo`.

- [ ] **Step 3: Build to confirm no errors**

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarViewModel.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add AIChatHistorySidebarViewModel"
```

---

### Task 3: AIChatHistorySidebarView (SwiftUI)

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarView.swift`

Depends on: Task 1 (UserText strings), Task 2 (ViewModel)

- [ ] **Step 1: Create the file**

```swift
//
//  AIChatHistorySidebarView.swift
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
import DesignResourcesKitIcons
import SwiftUI

struct AIChatHistorySidebarView: View {

    @ObservedObject var viewModel: AIChatHistorySidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            actionRows
            chatsSection
            Spacer(minLength: 0)
            Divider()
            footerView
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Duck.ai icon placeholder — swap for real asset when available
            Image(.aiChatAdd)
                .renderingMode(.template)
                .foregroundColor(.primary)
                .frame(width: 20, height: 20)
            Text(UserText.aiChatHistorySidebarTitle)
                .font(.headline)
            Spacer()
            Button {
                viewModel.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Action Rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                title: UserText.aiChatHistorySidebarNewChat,
                icon: Image(.aiChatAdd),
                action: { viewModel.onNewChat?() }
            )
            actionRow(
                title: UserText.aiChatHistorySidebarNewVoiceChat,
                icon: Image(.permissionMicrophone),
                action: { viewModel.onNewVoiceChat?() }
            )
            actionRow(
                title: UserText.aiChatHistorySidebarNewImage,
                icon: Image(.image),
                action: { viewModel.onNewImageChat?() }
            )
        }
        .padding(.vertical, 4)
    }

    private func actionRow(title: String, icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chats Section

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.aiChatHistorySidebarChatsHeader)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            chatListContent
        }
    }

    @ViewBuilder
    private var chatListContent: some View {
        if viewModel.isLoading && viewModel.chats.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if !viewModel.isLoading && viewModel.chats.isEmpty {
            Text(UserText.aiChatHistorySidebarNoChats)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .multilineTextAlignment(.center)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.chats) { suggestion in
                        chatRow(suggestion)
                    }
                }
            }
        }
    }

    private func chatRow(_ suggestion: AIChatSuggestion) -> some View {
        Button {
            viewModel.onChatSelected?(suggestion.chatId)
        } label: {
            HStack(spacing: 8) {
                Text(suggestion.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if suggestion.isPinned {
                    Image(.pin)
                        .renderingMode(.template)
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerView: some View {
        Button {
            viewModel.onSettings?()
        } label: {
            HStack(spacing: 8) {
                Image(.aiChatSettings)
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text(UserText.aiChatHistorySidebarSettingsAndMore)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

> **Note on icons:** This plan uses `Image(.aiChatAdd)`, `Image(.permissionMicrophone)`, `Image(.image)`, `Image(.pin)`, `Image(.aiChatSettings)` from `DesignResourcesKitIcons`. Check the exact SwiftUI initializer for your version — it may be `Image(DesignSystemImages.Glyphs.Size16.aiChatAdd)` or similar. Verify against the existing `AIChatHistoryMenuBuilder.swift` which uses AppKit equivalents (`DesignSystemImages.Glyphs.Size16.*`).

- [ ] **Step 2: Add to Xcode project**

- [ ] **Step 3: Build to confirm no errors**

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarView.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add AIChatHistorySidebarView (SwiftUI)"
```

---

### Task 4: AIChatHistorySidebarViewController

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarViewController.swift`

Depends on: Task 2 (ViewModel), Task 3 (View)

- [ ] **Step 1: Create the file**

```swift
//
//  AIChatHistorySidebarViewController.swift
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

/// NSViewController wrapper for AIChatHistorySidebarView.
/// Creates and owns the view model; the coordinator wires up closures via viewModel.
final class AIChatHistorySidebarViewController: NSViewController {

    let viewModel = AIChatHistorySidebarViewModel()
    private var hostingController: NSHostingController<AIChatHistorySidebarView>!

    override func loadView() {
        hostingController = NSHostingController(rootView: AIChatHistorySidebarView(viewModel: viewModel))
        addChild(hostingController)
        view = hostingController.view
    }
}
```

- [ ] **Step 2: Add to Xcode project**

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarViewController.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add AIChatHistorySidebarViewController"
```

---

### Task 5: AIChatHistorySidebarHosting protocol + BrowserTabViewController left container

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarHosting.swift`
- Modify: `macOS/DuckDuckGo/Tab/View/BrowserTabViewController.swift`

This task mirrors how `AIChatSidebarHosting.swift` and `BrowserTabViewController` work for the right sidebar.

- [ ] **Step 1: Create AIChatHistorySidebarHosting.swift**

```swift
//
//  AIChatHistorySidebarHosting.swift
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
import Foundation

/// Protocol that abstracts BrowserTabViewController's left-side history container
/// so AIChatHistorySidebarCoordinator can drive layout without a direct import.
@MainActor
protocol AIChatHistorySidebarHosting: AnyObject {
    /// Trailing constraint of the history container anchored to view.leadingAnchor.
    /// constant = 0 → hidden (off left edge); constant = historyWidth → fully visible.
    var historyContainerTrailingConstraint: NSLayoutConstraint? { get }

    /// Width constraint of the history container.
    var historyContainerWidthConstraint: NSLayoutConstraint? { get }

    /// Embeds the history sidebar VC into the left container once at setup.
    func embedHistorySidebarViewController(_ viewController: NSViewController)
}
```

- [ ] **Step 2: Add the history container to BrowserTabViewController.setupLayout()**

In `BrowserTabViewController.swift`, add the following stored properties near the existing sidebar constraint properties (around line 591):

```swift
private(set) var historyContainerTrailingConstraint: NSLayoutConstraint?
private(set) var historyContainerWidthConstraint: NSLayoutConstraint?
private(set) lazy var historyContainer = ColorView(
    frame: .zero,
    backgroundColor: .browserTabBackground,
    borderWidth: 0
)
```

Then in `setupLayout()`, after the existing `sidebarResizeHandle` block (after line 262), add:

```swift
// Left history sidebar container — mirrors the right sidebarContainer pattern.
// historyContainer.trailing = view.leading + 0 → hidden off left edge
// historyContainer.trailing = view.leading + width → fully on-screen
historyContainer.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(historyContainer)

historyContainerTrailingConstraint = historyContainer.trailingAnchor.constraint(
    equalTo: view.leadingAnchor,
    constant: 0
)
historyContainerWidthConstraint = historyContainer.widthAnchor.constraint(equalToConstant: 260)

NSLayoutConstraint.activate([
    historyContainer.topAnchor.constraint(equalTo: view.topAnchor),
    historyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    historyContainerTrailingConstraint!,
    historyContainerWidthConstraint!
])
```

- [ ] **Step 3: Update addWebViewToViewHierarchy to use historyContainer.trailingAnchor**

In `addWebViewToViewHierarchy(_:tab:)` (around line 609), change:

```swift
// BEFORE:
containerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
```

to:

```swift
// AFTER:
containerStackView.leadingAnchor.constraint(equalTo: historyContainer.trailingAnchor),
```

This makes the web content area start at the right edge of the history container. When the history sidebar is hidden (`historyContainer.trailing = view.leading + 0`), the web content starts at `view.leading` — same as before.

- [ ] **Step 4: Add BrowserTabViewController conformance to AIChatHistorySidebarHosting**

Add at the bottom of `AIChatHistorySidebarHosting.swift` (or as an extension in a separate file):

```swift
extension BrowserTabViewController: AIChatHistorySidebarHosting {

    func embedHistorySidebarViewController(_ viewController: NSViewController) {
        // Remove any previously embedded history sidebar VC
        children
            .filter { $0.view.superview === historyContainer }
            .forEach { $0.removeCompletely() }

        addAndLayoutChild(viewController, into: historyContainer)
    }
}
```

- [ ] **Step 5: Build and verify layout is unchanged**

Build and run in simulator/device. The app should look identical to before — the history container is hidden (off screen to the left, constant = 0).

- [ ] **Step 6: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarHosting.swift
git add macOS/DuckDuckGo/Tab/View/BrowserTabViewController.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add left history sidebar container to BrowserTabViewController"
```

---

### Task 6: AIChatHistorySidebarCoordinator

**Files:**
- Create: `macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarCoordinator.swift`

Depends on: Tasks 2, 4, 5

- [ ] **Step 1: Create the file**

```swift
//
//  AIChatHistorySidebarCoordinator.swift
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
import PrivacyConfig

@MainActor
final class AIChatHistorySidebarCoordinator {

    // MARK: - Constants

    private enum Constants {
        static let sidebarWidth: CGFloat = 260
        static let animationDuration: TimeInterval = 0.25
    }

    // MARK: - Public State

    @Published private(set) var isSidebarOpen: Bool = false

    // MARK: - Dependencies

    private let sidebarHost: AIChatHistorySidebarHosting
    private let suggestionsReader: AIChatSuggestionsReading
    private let aiChatTabOpener: AIChatTabOpening
    private let historySettings: AIChatHistorySettings

    // MARK: - Private State

    private let viewModel: AIChatHistorySidebarViewModel
    private var fetchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        sidebarHost: AIChatHistorySidebarHosting,
        suggestionsReader: AIChatSuggestionsReading,
        aiChatTabOpener: AIChatTabOpening,
        privacyConfig: PrivacyConfigurationManaging,
        viewModel: AIChatHistorySidebarViewModel
    ) {
        self.sidebarHost = sidebarHost
        self.suggestionsReader = suggestionsReader
        self.aiChatTabOpener = aiChatTabOpener
        self.historySettings = AIChatHistorySettings(privacyConfig: privacyConfig)
        self.viewModel = viewModel

        wireClosures()
    }

    // MARK: - Public API

    func toggleSidebar() {
        if isSidebarOpen {
            closeSidebar(animated: true)
        } else {
            openSidebar()
        }
    }

    func closeSidebar(animated: Bool) {
        guard isSidebarOpen else { return }
        isSidebarOpen = false
        cancelFetch()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.animationDuration
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarHost.historyContainerTrailingConstraint?.animator().constant = 0
            } completionHandler: { [weak self] in
                self?.clearViewModelState()
            }
        } else {
            sidebarHost.historyContainerTrailingConstraint?.constant = 0
            clearViewModelState()
        }
    }

    // MARK: - Private

    private func openSidebar() {
        cancelFetch()
        viewModel.update(chats: [], isLoading: true)
        isSidebarOpen = true

        sidebarHost.historyContainerWidthConstraint?.constant = Constants.sidebarWidth

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.animationDuration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sidebarHost.historyContainerTrailingConstraint?.animator().constant = Constants.sidebarWidth
        }

        fetchTask = Task { [weak self] in
            await self?.fetchAndPublish()
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    private func clearViewModelState() {
        viewModel.update(chats: [], isLoading: false)
    }

    private func fetchAndPublish() async {
        let result = await suggestionsReader.fetchSuggestions(query: nil)
        guard !Task.isCancelled else { return }

        let all = (result.pinned + result.recent).sorted {
            ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }

        viewModel.update(chats: all, isLoading: false)
    }

    private func wireClosures() {
        viewModel.onClose = { [weak self] in
            self?.closeSidebar(animated: true)
        }

        viewModel.onChatSelected = { [weak self] chatId in
            self?.aiChatTabOpener.openAIChatTab(
                with: .existingChat(chatId: chatId),
                behavior: .currentTab
            )
        }

        viewModel.onNewChat = { [weak self] in
            self?.aiChatTabOpener.openAIChatTab(with: .newChat, behavior: .currentTab)
        }

        viewModel.onNewVoiceChat = { [weak self] in
            guard let url = self?.buildModeURL(mode: AIChatURLParameters.voiceModeValue) else { return }
            self?.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .currentTab)
        }

        viewModel.onNewImageChat = { [weak self] in
            guard let url = self?.buildModeURL(mode: AIChatURLParameters.imageModeValue) else { return }
            self?.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .currentTab)
        }

        viewModel.onSettings = { _ in
            Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .aiChat)
        }
    }

    private func buildModeURL(mode: String) -> URL? {
        let settings = AIChatRemoteSettings()
        guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == AIChatURLParameters.modeName }
        items.append(URLQueryItem(name: AIChatURLParameters.modeName, value: mode))
        components.queryItems = items
        return components.url
    }
}
```

- [ ] **Step 2: Add to Xcode project**

- [ ] **Step 3: Build**

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarCoordinator.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: add AIChatHistorySidebarCoordinator"
```

---

### Task 7: MainViewController wiring

**Files:**
- Create: `macOS/DuckDuckGo/MainWindow/MainViewController+AIChatHistorySidebar.swift`
- Modify: `macOS/DuckDuckGo/MainWindow/MainViewController.swift`

Depends on: Tasks 4, 5, 6

- [ ] **Step 1: Create MainViewController+AIChatHistorySidebar.swift**

```swift
//
//  MainViewController+AIChatHistorySidebar.swift
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

extension MainViewController {

    /// Creates the history sidebar coordinator and wires it up.
    /// Call once from viewDidLoad, after aiChatCoordinator and browserTabViewController are ready.
    func setupAIChatHistorySidebar() {
        let historySidebarVC = AIChatHistorySidebarViewController()

        browserTabViewController.embedHistorySidebarViewController(historySidebarVC)

        aiChatHistorySidebarCoordinator = AIChatHistorySidebarCoordinator(
            sidebarHost: browserTabViewController,
            suggestionsReader: aiChatSuggestionsReader,
            aiChatTabOpener: aiChatTabOpener,
            privacyConfig: contentBlocking.privacyConfigurationManager,
            viewModel: historySidebarVC.viewModel
        )

        // When AI Chat sidebar opens, close history sidebar
        aiChatCoordinator.sidebarPresenceDidChangePublisher
            .filter { $0.isShown }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.aiChatHistorySidebarCoordinator?.closeSidebar(animated: false)
            }
            .store(in: &historySidebarCancellables)
    }
}
```

> **Note on `aiChatSuggestionsReader`:** You need a `SuggestionsReader` and `AIChatSuggestionsReader` available in `MainViewController`. These are already set up for the omnibar suggestions — find where `AIChatSuggestionsReader` is created (search for `AIChatSuggestionsReader` in the project) and reuse or expose the same instance. If it lives in `AIChatOmnibarController`, you may need to expose it or create a separate instance here.

- [ ] **Step 2: Add stored properties to MainViewController.swift**

In `MainViewController.swift`, add the following stored properties in the properties section:

```swift
// History sidebar
var aiChatHistorySidebarCoordinator: AIChatHistorySidebarCoordinator?
var historySidebarCancellables = Set<AnyCancellable>()
```

- [ ] **Step 3: Call setupAIChatHistorySidebar() from viewDidLoad**

In `MainViewController.viewDidLoad()` (or `viewWillAppear` — use whichever is called after `aiChatCoordinator` is set up), add:

```swift
setupAIChatHistorySidebar()
```

Place this after `aiChatCoordinator` is initialized (check the order in the existing `viewDidLoad` or `init`).

- [ ] **Step 4: Build**

- [ ] **Step 5: Commit**

```bash
git add macOS/DuckDuckGo/MainWindow/MainViewController+AIChatHistorySidebar.swift
git add macOS/DuckDuckGo/MainWindow/MainViewController.swift
git add macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj
git commit -m "feat: wire up AIChatHistorySidebarCoordinator in MainViewController"
```

---

### Task 8: Toolbar button in NavigationBarViewController

**Files:**
- Modify: `macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift`

Depends on: Task 7

The `goBackButton` is an `@IBOutlet` from a XIB, inserted into the `navigationButtons` NSStackView. We add a new programmatic button and insert it before `goBackButton` in the stack.

- [ ] **Step 1: Add the button property and setup**

In `NavigationBarViewController.swift`, add a stored property near the other button properties (around line 51):

```swift
private var aiChatHistoryButton: MouseOverButton!
```

- [ ] **Step 2: Create and insert the button in viewDidLoad**

In `viewDidLoad()` (or wherever other programmatic button setup happens — check existing patterns), add:

```swift
setupAIChatHistoryButton()
```

Add the helper method:

```swift
private func setupAIChatHistoryButton() {
    let button = MouseOverButton(
        image: NSImage(systemSymbolName: "clock", accessibilityDescription: nil) ?? NSImage(),
        target: self,
        action: #selector(aiChatHistoryButtonClicked)
    )
    button.translatesAutoresizingMaskIntoConstraints = false
    button.bezelStyle = .shadowlessSquare
    button.cornerRadius = 9
    button.mouseOverColor = .buttonMouseOver
    button.mouseDownColor = .buttonMouseDown
    button.isBordered = false
    button.refusesFirstResponder = true
    button.toolTip = "Duck.ai Chats"
    button.setAccessibilityIdentifier("NavigationBarViewController.AIChatHistoryButton")

    // Insert before goBackButton in the navigationButtons stack view
    if let goBackIndex = navigationButtons.arrangedSubviews.firstIndex(of: goBackButton) {
        navigationButtons.insertArrangedSubview(button, at: goBackIndex)
    } else {
        navigationButtons.insertArrangedSubview(button, at: 0)
    }

    // Match existing button size constraints
    button.widthAnchor.constraint(equalToConstant: goBackButtonWidthConstraint.constant).isActive = true
    button.heightAnchor.constraint(equalToConstant: goBackButtonHeightConstraint.constant).isActive = true

    aiChatHistoryButton = button
}
```

- [ ] **Step 3: Add the button action**

```swift
@objc private func aiChatHistoryButtonClicked() {
    aiChatCoordinator.toggleAIChatHistorySidebar()
}
```

This requires `NavigationBarViewController` to have access to the history sidebar coordinator. The existing `aiChatCoordinator: AIChatCoordinating` property is on `NavigationBarViewController`. You have two options:

**Option A (recommended):** Extend `AIChatCoordinating` with a `toggleAIChatHistorySidebar()` method that `MainViewController` routes to `aiChatHistorySidebarCoordinator`.

**Option B (simpler):** Add a closure property to `NavigationBarViewController`:

```swift
var onAIChatHistoryButtonClicked: (() -> Void)?
```

And in the action:
```swift
@objc private func aiChatHistoryButtonClicked() {
    onAIChatHistoryButtonClicked?()
}
```

Then in `MainViewController+AIChatHistorySidebar.swift` after creating the coordinator, set:
```swift
navigationBarViewController.onAIChatHistoryButtonClicked = { [weak self] in
    self?.aiChatHistorySidebarCoordinator?.toggleSidebar()
}
```

**Use Option B** — it's simpler and avoids modifying the `AIChatCoordinating` protocol.

- [ ] **Step 4: Update button active state**

The button should appear "active" (highlighted) when the history sidebar is open. In `MainViewController+AIChatHistorySidebar.swift`, add:

```swift
aiChatHistorySidebarCoordinator?.$isSidebarOpen
    .receive(on: DispatchQueue.main)
    .sink { [weak self] isOpen in
        // Use existing button highlight pattern
        self?.navigationBarViewController.updateAIChatHistoryButtonState(isActive: isOpen)
    }
    .store(in: &historySidebarCancellables)
```

Add to `NavigationBarViewController`:

```swift
func updateAIChatHistoryButtonState(isActive: Bool) {
    // Use the same active-state pattern as other toggle buttons in the bar.
    // Check how the AI chat omnibar button or bookmarks button shows active state,
    // and replicate that pattern here. Typically: set a highlighted background or
    // use `normalTintColor` vs an active color.
    aiChatHistoryButton?.isHighlighted = isActive
}
```

- [ ] **Step 5: Hide button in popup windows**

In the existing `updateButtons()` or similar method that hides buttons in popup windows, add:

```swift
aiChatHistoryButton?.isHidden = isInPopUpWindow
```

Find this by searching for `isInPopUpWindow` and `homeButton.isHidden` — they are toggled in the same method.

- [ ] **Step 6: Build and run**

Verify:
- Button appears to the left of the back button
- Button is hidden in popup windows
- Clicking button opens/closes the history sidebar
- Button shows active state when sidebar is open

- [ ] **Step 7: Commit**

```bash
git add macOS/DuckDuckGo/NavigationBar/View/NavigationBarViewController.swift
git commit -m "feat: add Duck.ai chat history toolbar button"
```

---

### Task 9: Mutual exclusion — close history sidebar when AI Chat opens

**Files:**
- Modify: `macOS/DuckDuckGo/MainWindow/MainViewController+AIChatHistorySidebar.swift`

This is already wired in Task 7 via `sidebarPresenceDidChangePublisher`. Verify the reverse direction also works:

- [ ] **Step 1: Verify AI Chat → history sidebar mutual exclusion**

When `AIChatCoordinator.toggleSidebar()` is called while the history sidebar is open, the history sidebar should close. This is handled by the Combine subscription in `setupAIChatHistorySidebar()`.

Open the app, open the history sidebar, then click the AI Chat toolbar button. The history sidebar should close immediately and the AI Chat sidebar should animate in.

- [ ] **Step 2: Verify history sidebar → AI Chat mutual exclusion**

In `AIChatHistorySidebarCoordinator.openSidebar()`, add the AI Chat collapse call. This requires access to `AIChatCoordinating`. Pass it as a dependency:

In `AIChatHistorySidebarCoordinator.init`, add parameter:
```swift
private let aiChatCoordinator: AIChatCoordinating
```

Update `openSidebar()`:
```swift
private func openSidebar() {
    // Close AI Chat sidebar if open
    aiChatCoordinator.collapseSidebar(withAnimation: false)
    // ... rest of open logic
}
```

Update `MainViewController+AIChatHistorySidebar.swift` to pass `aiChatCoordinator`:
```swift
aiChatHistorySidebarCoordinator = AIChatHistorySidebarCoordinator(
    sidebarHost: browserTabViewController,
    aiChatCoordinator: aiChatCoordinator,
    suggestionsReader: aiChatSuggestionsReader,
    aiChatTabOpener: aiChatTabOpener,
    privacyConfig: contentBlocking.privacyConfigurationManager,
    viewModel: historySidebarVC.viewModel
)
```

- [ ] **Step 3: Build and test both directions**

- [ ] **Step 4: Commit**

```bash
git add macOS/DuckDuckGo/AIChat/Sidebar/AIChatHistorySidebarCoordinator.swift
git add macOS/DuckDuckGo/MainWindow/MainViewController+AIChatHistorySidebar.swift
git commit -m "feat: enforce mutual exclusion between history and AI Chat sidebars"
```

---

### Task 10: Final integration verification

- [ ] **Step 1: Build and run the app**

- [ ] **Step 2: Verify history sidebar opens**

Click the history button (clock icon left of back button). The left sidebar should animate in with the Duck.ai header, action rows (New Chat, New Voice Chat, New Image), Chats section, and Settings & More footer.

- [ ] **Step 3: Verify chat list loads**

If there are Duck.ai chats in the browser's localStorage, they should appear. If not, verify the empty state "No recent chats" shows correctly. Verify loading spinner shows briefly before content.

- [ ] **Step 4: Verify chat selection**

Click a chat. The current tab should navigate to that Duck.ai chat. The history sidebar should remain open.

- [ ] **Step 5: Verify action buttons**

Click New Chat → opens duck.ai new chat in current tab.
Click New Voice Chat → opens duck.ai with `?mode=voice`.
Click New Image → opens duck.ai with `?mode=image`.
Click Settings & More → opens preferences pane at AI Chat section.

- [ ] **Step 6: Verify mutual exclusion**

Open history sidebar → open AI Chat sidebar → history sidebar should close.
Open AI Chat sidebar → open history sidebar → AI Chat sidebar should close.

- [ ] **Step 7: Verify close button**

Click the X in the header. Sidebar animates out.

- [ ] **Step 8: Verify popup window**

Open a popup window (right-click a link → Open in New Window or similar). History button should not appear in the toolbar.

- [ ] **Step 9: Final commit**

```bash
git commit --allow-empty -m "feat: Duck.ai chat history sidebar complete

- Native left-side sidebar with chat history
- Toolbar button left of back/forward buttons
- Mutual exclusion with AI Chat right sidebar
- Reuses AIChatSuggestionsReader for data
- New Chat / Voice / Image / Settings actions"
```

---

## Known Limitations / Follow-up

- `addAndLayoutChildBesideSidebar` (for non-web content like bookmarks) still constrains leading to `view.leading` — it does not push alongside the history sidebar. This is acceptable for v1.
- No per-item context menu (rename, delete, pin) — deferred per spec.
- No resize handle — fixed 260pt width.
- No state persistence — sidebar always starts closed.
- Unit tests deferred to a separate pass.
