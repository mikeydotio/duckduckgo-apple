//
//  AIChatStateProvider.swift
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
import Combine
import Foundation
import FeatureFlags
import PrivacyConfig

typealias TabIdentifier = String
typealias AIChatStatesByTab = [TabIdentifier: AIChatState]

/// A protocol that defines the interface for managing per-tab AI Chat state.
/// This provider handles the lifecycle and state of AI Chat sessions across multiple browser tabs.
protocol AIChatStateProviding: AnyObject {
    /// The minimum allowed sidebar width in points.
    var minSidebarWidth: CGFloat { get }

    /// The maximum allowed sidebar width in points.
    var maxSidebarWidth: CGFloat { get }

    /// The initial sidebar width used when no user preference exists.
    var defaultSidebarWidth: CGFloat { get }

    /// Persists a new sidebar width for the given tab and updates the global default.
    func setSidebarWidth(_ width: CGFloat, for tabID: TabIdentifier)

    /// Returns the existing cached chat view controller for the specified tab, if one exists.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: An `AIChatViewController` instance associated with the tab, or `nil` if no view controller exists
    func getChatViewController(for tabID: TabIdentifier) -> AIChatViewController?

    /// Creates and caches a new chat view controller for the specified tab.
    /// - Parameters:
    ///   - tabID: The unique identifier of the tab
    ///   - burnerMode: The burner mode configuration for the sidebar
    /// - Returns: A newly created `AIChatViewController` instance
    func makeChatViewController(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatViewController

    /// Checks if a sidebar is currently being displayed for the specified tab.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: `true` if the sidebar is showing, `false` otherwise
    func isShowingSidebar(for tabID: TabIdentifier) -> Bool

    /// Handles cleanup when a sidebar is closed by the user.
    /// - Parameter tabID: The unique identifier of the tab whose sidebar was closed
    func handleSidebarDidClose(for tabID: TabIdentifier)

    /// Removes sidebars for tabs that are no longer active.
    /// - Parameter currentTabIDs: Array of tab IDs that are currently open
    func cleanUp(for currentTabIDs: [TabIdentifier])

    /// Resets the sidebar state for the specified tab
    /// This clears any saved URL (with chatID) and restoration data.
    /// - Parameter tabID: The unique identifier of the tab
    func resetSidebar(for tabID: TabIdentifier)

    /// Clears the sidebar for the specified tab if the session has expired.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: `true` if the sidebar was cleared due to session expiry, `false` otherwise
    @discardableResult
    func clearSidebarIfSessionExpired(for tabID: TabIdentifier) -> Bool

    /// All active AI Chat states mapped by their tab identifiers.
    var statesByTab: AIChatStatesByTab { get }

    /// Publishes events whenever `statesByTab` gets updated.
    var statesByTabPublisher: AnyPublisher<AIChatStatesByTab, Never> { get }

    /// Restores the provider's state from a previously saved model.
    /// This method cleans up all existing states and replaces the current model with the provided one.
    /// - Parameter statesByTab: The state model to restore, containing tab IDs mapped to their AI Chat states
    func restoreState(_ statesByTab: AIChatStatesByTab)
}

final class AIChatStateProvider: AIChatStateProviding {

    enum Constants {
        static let defaultSidebarWidth: CGFloat = 400
        static let minSidebarWidth: CGFloat = 320
        static let maxSidebarWidth: CGFloat = 900
    }

    private let featureFlagger: FeatureFlagger
    private var preferencesStorage: AIChatPreferencesStorage

    var defaultSidebarWidth: CGFloat { Constants.defaultSidebarWidth }
    var minSidebarWidth: CGFloat { Constants.minSidebarWidth }
    var maxSidebarWidth: CGFloat { Constants.maxSidebarWidth }

    func setSidebarWidth(_ width: CGFloat, for tabID: TabIdentifier) {
        statesByTab[tabID]?.sidebarWidth = width
        preferencesStorage.lastUsedSidebarWidth = Double(width)
    }

    @Published private(set) var statesByTab: AIChatStatesByTab

    var statesByTabPublisher: AnyPublisher<AIChatStatesByTab, Never> {
        $statesByTab.dropFirst().eraseToAnyPublisher()
    }

    private var shouldKeepSession: Bool {
        featureFlagger.isFeatureOn(.aiChatKeepSession)
    }

    init(statesByTab: AIChatStatesByTab? = nil,
         featureFlagger: FeatureFlagger,
         preferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()) {
        self.statesByTab = statesByTab ?? [:]
        self.featureFlagger = featureFlagger
        self.preferencesStorage = preferencesStorage
    }

    func getChatViewController(for tabID: TabIdentifier) -> AIChatViewController? {
        return statesByTab[tabID]?.chatViewController
    }

    func makeChatViewController(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatViewController {
        let chatState = getCurrentState(for: tabID, burnerMode: burnerMode)

        if let existingViewController = chatState.chatViewController {
            return existingViewController
        }

        let chatViewController = AIChatViewController(currentAIChatURL: chatState.currentAIChatURL, burnerMode: burnerMode)
        chatViewController.tabID = tabID
        if let restorationData = chatState.restorationData {
            chatViewController.setAIChatRestorationData(restorationData)
        }
        chatState.chatViewController = chatViewController

        return chatViewController
    }

    private func getCurrentState(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatState {
        let aiChatRemoteSettings = AIChatRemoteSettings()
        var currentState = statesByTab[tabID]

        if let existingState = currentState,
           let hiddenAt = existingState.hiddenAt,
           hiddenAt.minutesSinceNow() > aiChatRemoteSettings.sessionTimeoutMinutes {
            existingState.persistStateAndReset(persistingState: shouldKeepSession)
            statesByTab.removeValue(forKey: tabID)

            currentState = nil
        }

        return currentState ?? makeState(for: tabID, burnerMode: burnerMode)
    }

    private func makeState(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatState {
        let chatState = AIChatState(burnerMode: burnerMode)
        statesByTab[tabID] = chatState
        return chatState
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        statesByTab[tabID]?.isPresented ?? false
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        statesByTab[tabID]?.persistStateAndReset(persistingState: shouldKeepSession)

        // If keep session is disables always remove sidebar data model
        if !shouldKeepSession {
            statesByTab.removeValue(forKey: tabID)
        }
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(statesByTab.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
            statesByTab.removeValue(forKey: tabID)
        }
    }

    func restoreState(_ statesByTab: AIChatStatesByTab) {
        cleanUp(for: [])
        self.statesByTab = statesByTab
    }

    func resetSidebar(for tabID: TabIdentifier) {
        statesByTab.removeValue(forKey: tabID)
    }

    @discardableResult
    func clearSidebarIfSessionExpired(for tabID: TabIdentifier) -> Bool {
        guard let existingState = statesByTab[tabID],
              existingState.isSessionExpired else {
            return false
        }

        existingState.persistStateAndReset(persistingState: shouldKeepSession)
        statesByTab.removeValue(forKey: tabID)
        return true
    }
}
