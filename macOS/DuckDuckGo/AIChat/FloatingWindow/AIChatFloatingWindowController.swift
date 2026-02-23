//
//  AIChatFloatingWindowController.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine

@MainActor
protocol AIChatFloatingWindowControllerDelegate: AnyObject {
    /// The user closed the floating window (via close button or Escape).
    func floatingWindowDidClose(_ controller: AIChatFloatingWindowController)
    /// The user clicked the attach/dock button to reattach the sidebar.
    func floatingWindowDidRequestDock(_ controller: AIChatFloatingWindowController)
}

/// Manages a single detached AI Chat floating window for one tab.
///
/// Each instance owns one `AIChatFloatingWindow` and the
/// `AIChatViewController` that was moved out of the docked sidebar.
@MainActor
final class AIChatFloatingWindowController: NSObject {

    private enum Constants {
        static let windowTitleSeparator = "\u{30FB}"
    }

    weak var delegate: AIChatFloatingWindowControllerDelegate?

    /// The tab this floating window is associated with.
    let tabID: TabIdentifier

    private let floatingWindow: AIChatFloatingWindow
    private var chatViewController: AIChatViewController?
    private var cancellables = Set<AnyCancellable>()

    var isShowing: Bool {
        floatingWindow.isVisible
    }

    init(tabID: TabIdentifier,
         chatViewController: AIChatViewController,
         tabViewModel: TabViewModel?,
         contentRect: NSRect) {
        self.tabID = tabID
        self.chatViewController = chatViewController
        self.floatingWindow = AIChatFloatingWindow(contentRect: contentRect)
        super.init()

        embedChatViewController(chatViewController)
        subscribeToTabInfo(tabViewModel)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: floatingWindow)
            .sink { [weak self] _ in
                guard let self else { return }
                self.delegate?.floatingWindowDidClose(self)
            }
            .store(in: &cancellables)
    }

    func show() {
        floatingWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        floatingWindow.close()
    }

    /// Removes the chat view controller from the floating window so it can be
    /// re-embedded in the docked sidebar. Returns `nil` if already detached.
    func detachChatViewController() -> AIChatViewController? {
        guard let vc = chatViewController else { return nil }
        floatingWindow.contentViewController = nil
        chatViewController = nil
        return vc
    }

    // MARK: - Private

    private func subscribeToTabInfo(_ tabViewModel: TabViewModel?) {
        guard let tabViewModel else { return }

        tabViewModel.$title.combineLatest(tabViewModel.$favicon)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, favicon in
                self?.chatViewController?.updateFloatingTitle(title, favicon: favicon)
                self?.floatingWindow.title = self?.windowTitle(for: title) ?? UserText.aiChatSidebarTitle
            }
            .store(in: &cancellables)
    }

    private func windowTitle(for pageTitle: String) -> String {
        let trimmedPageTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPageTitle.isEmpty else {
            return UserText.aiChatSidebarTitle
        }
        return "\(UserText.aiChatSidebarTitle)\(Constants.windowTitleSeparator)\(trimmedPageTitle)"
    }

    private func embedChatViewController(_ viewController: AIChatViewController) {
        floatingWindow.contentViewController = viewController
    }
}
