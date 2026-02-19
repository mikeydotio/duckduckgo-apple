//
//  AIChatPresenter.swift
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

import AIChat
import AppKit
import Combine
import FeatureFlags
import PixelKit
import PrivacyConfig

/// Represents an event of hiding or showing an AI Chat tab sidebar.
///
/// - Note: This only refers to the logic of tab having sidebar shown or hidden,
///         not to sidebars getting on and off the screen due to switching browser tabs.
struct AIChatPresenceChange: Equatable {
    let tabID: TabIdentifier
    let isShown: Bool
}

/// Manages the presentation of an AI Chat sidebar in the browser.
///
/// Handles visibility, state management, and feature flag coordination for the AI Chat sidebar.
@MainActor
protocol AIChatPresenting {

    /// Toggles the AI Chat sidebar visibility on a current tab, using appropriate animation.
    func toggleSidebar()

    /// Collapses the AI Chat sidebar on the current tab with or without animation.
    func collapseSidebar(withAnimation: Bool)

    /// Returns whether the AI Chat sidebar is open on a tab specified by `tabID`.
    func isSidebarOpen(for tabID: TabIdentifier) -> Bool

    /// Returns whether the AI Chat sidebar is currently open for the active tab.
    func isSidebarOpenForCurrentTab() -> Bool

    /// Returns the date when the AI Chat sidebar was last hidden for a tab specified by `tabID`.
    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date?

    /// Returns the date when the AI Chat sidebar was last hidden for the active tab.
    func sidebarHiddenAtForCurrentTab() -> Date?

    /// Emits events whenever sidebar is shown or hidden for a tab.
    var sidebarPresenceWillChangePublisher: AnyPublisher<AIChatPresenceChange, Never> { get }

    /// Returns whether the AI Chat sidebar is detached into a floating window for a tab specified by `tabID`.
    func isSidebarDetached(for tabID: TabIdentifier) -> Bool

    /// Emits a `tabID` whenever a sidebar is detached, reattached, or its floating window is closed.
    var sidebarDetachStateDidChangePublisher: AnyPublisher<TabIdentifier, Never> { get }

    /// Brings the detached floating window for `tabID` to the front and makes it key.
    func focusFloatingWindow(for tabID: TabIdentifier)

    /// Consumes `prompt` and presents it in the sidebar. Appends to existing conversation if that was present.
    func presentSidebar(for prompt: AIChatNativePrompt)
}

final class AIChatPresenter: AIChatPresenting {

    let sidebarPresenceWillChangePublisher: AnyPublisher<AIChatPresenceChange, Never>
    let sidebarDetachStateDidChangePublisher: AnyPublisher<TabIdentifier, Never>

    private let sidebarHost: AIChatSidebarHosting
    private let stateProvider: AIChatStateProviding
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?
    private let featureFlagger: FeatureFlagger
    private let sidebarPresenceWillChangeSubject = PassthroughSubject<AIChatPresenceChange, Never>()
    private let sidebarDetachStateDidChangeSubject = PassthroughSubject<TabIdentifier, Never>()

    private var isAnimatingSidebarTransition: Bool = false
    private var isResizeDragging: Bool = false
    private var resizePixelDebounceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Per-window default width, snapshotted from the global preference at init.
    /// Updated only by resizes happening in this window.
    private var windowDefaultWidth: CGFloat

    private var isSidebarResizable: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebarResizable)
    }

    private var isSidebarFloatingEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatSidebarFloating)
    }

    init(
        sidebarHost: AIChatSidebarHosting,
        stateProvider: AIChatStateProviding,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
        aiChatTabOpener: AIChatTabOpening,
        windowControllersManager: WindowControllersManagerProtocol,
        pixelFiring: PixelFiring?,
        featureFlagger: FeatureFlagger,
        preferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()
    ) {
        self.sidebarHost = sidebarHost
        self.stateProvider = stateProvider
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger

        if let stored = preferencesStorage.lastUsedSidebarWidth, stored > 0 {
            let min = stateProvider.minSidebarWidth
            let max = stateProvider.maxSidebarWidth
            self.windowDefaultWidth = Swift.min(max, Swift.max(min, CGFloat(stored)))
        } else {
            self.windowDefaultWidth = stateProvider.defaultSidebarWidth
        }

        sidebarPresenceWillChangePublisher = sidebarPresenceWillChangeSubject.eraseToAnyPublisher()
        sidebarDetachStateDidChangePublisher = sidebarDetachStateDidChangeSubject.eraseToAnyPublisher()
        self.sidebarHost.aiChatSidebarHostingDelegate = self
        self.sidebarHost.aiChatSidebarResizeDelegate = self

        NotificationCenter.default.publisher(for: .aiChatNativeHandoffData)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard sidebarHost.isInKeyWindow,
                      let payload = notification.object as? AIChatPayload
                else { return }

                self?.handleAIChatHandoff(with: payload)
            }
            .store(in: &cancellables)
    }

    func toggleSidebar() {
        guard !isAnimatingSidebarTransition,
              let currentTabID = sidebarHost.currentTabID else { return }

        let willShowSidebar = !stateProvider.isShowingSidebar(for: currentTabID)

        updateSidebarConstraints(for: currentTabID, isShowingSidebar: willShowSidebar, withAnimation: true)
    }

    func collapseSidebar(withAnimation: Bool) {
        guard let currentTabID = sidebarHost.currentTabID else { return }
        updateSidebarConstraints(for: currentTabID, isShowingSidebar: false, withAnimation: withAnimation)
    }

    func isSidebarOpen(for tabID: TabIdentifier) -> Bool {
        return stateProvider.isShowingSidebar(for: tabID)
    }

    func isSidebarOpenForCurrentTab() -> Bool {
        guard let currentTabID = sidebarHost.currentTabID else { return false }
        return isSidebarOpen(for: currentTabID)
    }

    func isSidebarDetached(for tabID: TabIdentifier) -> Bool {
        stateProvider.statesByTab[tabID]?.isDetached ?? false
    }

    func focusFloatingWindow(for tabID: TabIdentifier) {
        stateProvider.statesByTab[tabID]?.floatingWindowController?.show()
    }

    func sidebarHiddenAt(for tabID: TabIdentifier) -> Date? {
        stateProvider.statesByTab[tabID]?.hiddenAt
    }

    func sidebarHiddenAtForCurrentTab() -> Date? {
        guard let currentTabID = sidebarHost.currentTabID else { return nil }
        return sidebarHiddenAt(for: currentTabID)
    }

    private func updateSidebarConstraints(for tabID: TabIdentifier, isShowingSidebar: Bool, withAnimation: Bool) {
        isAnimatingSidebarTransition = true
        sidebarPresenceWillChangeSubject.send(.init(tabID: tabID, isShown: isShowingSidebar))

        // Hide resize handle immediately when the sidebar starts any transition.
        // Also reset the drag flag in case a transition interrupts an active drag.
        sidebarHost.setResizeHandleVisible(false)
        isResizeDragging = false

        if isShowingSidebar {
            stateProvider.clearSidebarIfSessionExpired(for: tabID)

            let chatViewController: AIChatViewController = {
                if let existingViewController = stateProvider.getChatViewController(for: tabID) {
                    return existingViewController
                } else {
                    return stateProvider.makeChatViewController(for: tabID, burnerMode: sidebarHost.burnerMode)
                }
            }()

            chatViewController.delegate = self
            sidebarHost.embedChatViewController(chatViewController, for: nil)

            // Mark sidebar as revealed when it's being shown
            stateProvider.statesByTab[tabID]?.setRevealed()
        } else {
            // Mark sidebar as hidden when it's being hidden
            stateProvider.statesByTab[tabID]?.setHidden()
        }

        let tabWidth = sidebarWidth(for: tabID)
        let displayWidth = isShowingSidebar ? effectiveSidebarWidth(tabWidth: tabWidth, availableWidth: sidebarHost.availableWidth) : tabWidth
        let newConstraintValue = isShowingSidebar ? -displayWidth : 0.0

        sidebarHost.sidebarContainerWidthConstraint?.constant = displayWidth

        if withAnimation {
            NSAnimationContext.runAnimationGroup { [weak self] context in
                guard let self else { return }

                context.duration = 0.25
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarHost.sidebarContainerLeadingConstraint?.animator().constant = newConstraintValue
            } completionHandler: { [weak self, tabID = sidebarHost.currentTabID] in
                guard let self else { return }
                self.isAnimatingSidebarTransition = false

                if isShowingSidebar && self.isSidebarResizable {
                    // Show the resize handle only after the open animation finishes
                    self.sidebarHost.setResizeHandleVisible(true)
                }

                guard let tabID, !isShowingSidebar else { return }
                self.stateProvider.statesByTab[tabID]?.tearDownUI()
                self.stateProvider.handleSidebarDidClose(for: tabID)
            }
        } else {
            sidebarHost.sidebarContainerLeadingConstraint?.constant = newConstraintValue

            if isShowingSidebar && isSidebarResizable {
                sidebarHost.setResizeHandleVisible(true)
            }

            if let tabID = sidebarHost.currentTabID, !isShowingSidebar {
                stateProvider.statesByTab[tabID]?.tearDownUI()
                stateProvider.handleSidebarDidClose(for: tabID)
            }
            self.isAnimatingSidebarTransition = false
        }
    }

    func presentSidebar(for prompt: AIChatNativePrompt) {
        guard let currentTabID = sidebarHost.currentTabID else { return }

        if let chatViewController = stateProvider.getChatViewController(for: currentTabID) {
            // If sidebar is open append conversation with prompt
            chatViewController.setAIChatPrompt(prompt)
        } else {
            AIChatPromptHandler.shared.setData(prompt)
            // If not showing the sidebar, open it with the prompt
            updateSidebarConstraints(for: currentTabID, isShowingSidebar: true, withAnimation: true)
        }
    }

    private func handleAIChatHandoff(with payload: AIChatPayload) {
        guard let currentTabID = sidebarHost.currentTabID else { return }

        let isShowingSidebar = stateProvider.isShowingSidebar(for: currentTabID)

        if !isShowingSidebar {
            /// https://app.asana.com/1/137249556945/project/276630244458377/task/1211982069731816
            stateProvider.resetSidebar(for: currentTabID)

            // If not showing the sidebar open it with the payload received
            let chatViewController = stateProvider.makeChatViewController(for: currentTabID, burnerMode: sidebarHost.burnerMode)
            chatViewController.aiChatPayload = payload
            updateSidebarConstraints(for: currentTabID, isShowingSidebar: true, withAnimation: true)
            pixelFiring?.fire(
                AIChatPixel.aiChatSidebarOpened(
                    source: .serp,
                    shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                    minutesSinceSidebarHidden: sidebarHiddenAt(for: currentTabID)?.minutesSinceNow()
                ),
                frequency: .dailyAndStandard
            )
        } else {
            // If sidebar is open then pass the payload to a new AIChat tab
            aiChatTabOpener.openAIChatTab(with: .payload(payload), behavior: .newTab(selected: true))
        }
    }

    // MARK: - Detach / Attach

    /// Moves the current tab's docked sidebar into a floating window.
    private func detachSidebar() {
        guard isSidebarFloatingEnabled,
              let tabID = sidebarHost.currentTabID,
              let chatState = stateProvider.statesByTab[tabID],
              let chatViewController = chatState.chatViewController,
              chatState.floatingWindowController == nil else { return }

        let screenFrame = sidebarHost.sidebarContainerScreenFrame ?? NSRect(x: 200, y: 200, width: 400, height: 600)

        collapseSidebarPreservingWebView(chatViewController, for: tabID)

        let tabViewModel = windowControllersManager.allTabCollectionViewModels
            .flatMap(\.tabViewModels)
            .first(where: { $0.key.uuid == tabID })?.value

        let controller = AIChatFloatingWindowController(
            tabID: tabID,
            chatViewController: chatViewController,
            tabViewModel: tabViewModel,
            contentRect: screenFrame)
        controller.delegate = self

        chatState.floatingWindowController = controller
        chatState.setDetached()

        controller.show()
        sidebarDetachStateDidChangeSubject.send(tabID)
    }

    /// Docks a floating sidebar back into the browser window for the given tab.
    private func attachSidebar(for tabID: TabIdentifier) {
        guard let chatState = stateProvider.statesByTab[tabID],
              let controller = chatState.floatingWindowController,
              let chatViewController = controller.detachChatViewController() else { return }

        chatState.setDocked()

        windowControllersManager.lastKeyMainWindowController?.window?.makeKeyAndOrderFront(nil)

        chatViewController.delegate = self
        sidebarHost.embedChatViewController(chatViewController, for: tabID)
        chatState.setRevealed()

        updateSidebarConstraints(for: tabID, isShowingSidebar: true, withAnimation: false)

        controller.delegate = nil
        controller.close()

        sidebarDetachStateDidChangeSubject.send(tabID)
    }
}

extension AIChatPresenter: AIChatSidebarHostingDelegate {

    func sidebarHostDidSelectTab(with tabID: TabIdentifier) {
        let shouldShowSidebar = isSidebarOpen(for: tabID)
        updateSidebarConstraints(for: tabID, isShowingSidebar: shouldShowSidebar, withAnimation: false)
    }

    func sidebarHostDidUpdateTabs() {
        let allPinnedTabIDs = windowControllersManager.pinnedTabsManagerProvider.currentPinnedTabManagers.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        let allTabIDs = windowControllersManager.allTabCollectionViewModels.flatMap { $0.tabViewModels.keys }.map { $0.uuid }
        let currentTabIDs = Set(allPinnedTabIDs + allTabIDs)

        let removedTabIDs = Set(stateProvider.statesByTab.keys).subtracting(currentTabIDs)
        for tabID in removedTabIDs {
            stateProvider.statesByTab[tabID]?.tearDownUI()
        }

        stateProvider.cleanUp(for: Array(currentTabIDs))
    }
}

extension AIChatPresenter: AIChatViewControllerDelegate {

    func didClickOpenInNewTabButton() {
        guard let currentTabID = sidebarHost.currentTabID,
              let chatState = stateProvider.statesByTab[currentTabID] else { return }

        pixelFiring?.fire(AIChatPixel.aiChatSidebarExpanded, frequency: .dailyAndStandard)

        let restorationData = chatState.restorationData
        let currentAIChatURL = chatState.currentAIChatURL.removingAIChatPlacementParameter()

        toggleSidebar()

        Task { @MainActor in
            if let data = restorationData {
                aiChatTabOpener.openAIChatTab(with: .restoration(data), behavior: .newTab(selected: true))
            } else {
                aiChatTabOpener.openAIChatTab(with: .url(currentAIChatURL), behavior: .newTab(selected: true))
            }
        }
    }

    func didClickCloseButton() {
        pixelFiring?.fire(AIChatPixel.aiChatSidebarClosed(source: .sidebarCloseButton), frequency: .dailyAndStandard)

        windowControllersManager.lastKeyMainWindowController?.window?.makeFirstResponder(nil)
        toggleSidebar()
    }

    func didClickDetachButton() {
        detachSidebar()
    }

    func didClickAttachButton(for tabID: TabIdentifier) {
        attachSidebar(for: tabID)
    }

    func didClickTitleButton(for tabID: TabIdentifier) {
        windowControllersManager.lastKeyMainWindowController?.window?.makeKeyAndOrderFront(nil)
        sidebarHost.selectTab(with: tabID)
    }
}

// MARK: - AIChatSidebarResizeDelegate

extension AIChatPresenter: AIChatSidebarResizeDelegate {

    @discardableResult
    func sidebarHostDidResize(to width: CGFloat) -> CGFloat {
        guard !isAnimatingSidebarTransition else { return width }
        isResizeDragging = true
        let clampedWidth = clampSidebarWidth(width)
        sidebarHost.applySidebarWidth(clampedWidth)
        return clampedWidth
    }

    func sidebarHostDidFinishResize(to width: CGFloat) {
        guard !isAnimatingSidebarTransition,
              let currentTabID = sidebarHost.currentTabID else { return }
        isResizeDragging = false
        let clampedWidth = clampSidebarWidth(width)
        sidebarHost.applySidebarWidth(clampedWidth)
        windowDefaultWidth = clampedWidth
        stateProvider.setSidebarWidth(clampedWidth, for: currentTabID)
        fireResizedPixelDebounced(width: clampedWidth)
    }

    func sidebarHostDidChangeAvailableWidth(_ availableWidth: CGFloat) {
        guard !isAnimatingSidebarTransition,
              !isResizeDragging,
              let currentTabID = sidebarHost.currentTabID,
              isSidebarOpen(for: currentTabID) else { return }
        let tabWidth = sidebarWidth(for: currentTabID)
        let effectiveWidth = effectiveSidebarWidth(tabWidth: tabWidth, availableWidth: availableWidth)
        sidebarHost.applySidebarWidth(effectiveWidth)
    }

    // MARK: - Private Helpers

    /// Hides the docked sidebar container visually without running the full close flow.
    ///
    /// Unlike `collapseSidebar`, this does not call `handleSidebarDidClose` which
    /// would unload the web view. Used when detaching, so the sidebar VC can be
    /// moved to a floating window with its content intact.
    private func collapseSidebarPreservingWebView(_ chatViewController: NSViewController, for tabID: TabIdentifier) {
        chatViewController.removeCompletely()
        sidebarHost.sidebarContainerLeadingConstraint?.constant = 0
        sidebarHost.setResizeHandleVisible(false)
        sidebarPresenceWillChangeSubject.send(.init(tabID: tabID, isShown: false))
    }

    /// Debounces the resize pixel so rapid adjustments only fire once (after 500 ms).
    private func fireResizedPixelDebounced(width: CGFloat) {
        resizePixelDebounceWorkItem?.cancel()
        let widthInt = Int(width)
        let workItem = DispatchWorkItem { [weak self] in
            self?.pixelFiring?.fire(AIChatPixel.aiChatSidebarResized(width: widthInt), frequency: .dailyAndStandard)
        }
        resizePixelDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Returns the sidebar width for a tab, falling back to this window's default.
    private func sidebarWidth(for tabID: TabIdentifier) -> CGFloat {
        stateProvider.statesByTab[tabID]?.sidebarWidth ?? windowDefaultWidth
    }

    /// Clamps a proposed sidebar width to the allowed range.
    /// The sidebar can never exceed half of the available window width,
    /// but the minimum width always takes precedence over the half-window cap.
    private func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
        let minWidth = stateProvider.minSidebarWidth
        let maxWidth = max(minWidth, min(stateProvider.maxSidebarWidth, sidebarHost.availableWidth / 2))
        return min(maxWidth, max(minWidth, width))
    }

    /// Computes the effective sidebar width for the given available width.
    ///
    /// - When the webview area is wider than the tab's chosen sidebar width,
    ///   the sidebar keeps its stored width.
    /// - When the window shrinks so the webview would be narrower than the sidebar,
    ///   both shrink proportionally (50/50) until the sidebar reaches its minimum.
    private func effectiveSidebarWidth(tabWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let minWidth = stateProvider.minSidebarWidth

        // Enough room: webview is at least as wide as the sidebar
        if availableWidth >= 2 * tabWidth {
            return tabWidth
        }

        // Not enough room: split 50/50, but respect the minimum
        let halfWidth = availableWidth / 2
        return max(minWidth, halfWidth)
    }
}

// MARK: - AIChatFloatingWindowControllerDelegate

extension AIChatPresenter: AIChatFloatingWindowControllerDelegate {

    func floatingWindowDidClose(_ controller: AIChatFloatingWindowController) {
        let tabID = controller.tabID
        let chatState = stateProvider.statesByTab[tabID]
        chatState?.setDocked()
        chatState?.setHidden()
        sidebarDetachStateDidChangeSubject.send(tabID)
    }

    func floatingWindowDidRequestDock(_ controller: AIChatFloatingWindowController) {
        attachSidebar(for: controller.tabID)
    }
}
