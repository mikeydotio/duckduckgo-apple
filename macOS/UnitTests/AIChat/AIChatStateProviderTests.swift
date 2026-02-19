//
//  AIChatStateProviderTests.swift
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
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatStateProviderTests: XCTestCase {

    var provider: AIChatStateProvider!

    override func setUp() {
        super.setUp()
        provider = AIChatStateProvider(featureFlagger: MockFeatureFlagger())
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultParameters_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatStateProvider(featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertTrue(provider.statesByTab.isEmpty)
        XCTAssertEqual(provider.defaultSidebarWidth, AIChatStateProvider.Constants.defaultSidebarWidth)
    }

    func testInit_withProvidedSidebarsByTab_setsDictionary() {
        // Given
        let testSidebar = AIChatState(burnerMode: .regular)
        let statesByTab = ["tab1": testSidebar]

        // When
        let provider = AIChatStateProvider(statesByTab: statesByTab, featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertNotNil(provider.statesByTab["tab1"])
    }

    func testInit_withNilParameter_setsEmptyDictionary() {
        // Given & When
        let provider = AIChatStateProvider(statesByTab: nil, featureFlagger: MockFeatureFlagger())

        // Then
        XCTAssertTrue(provider.statesByTab.isEmpty)
    }

    // MARK: - Get Sidebar Tests

    func testGetSidebarViewController_withExistingTab_returnsViewController() {
        // Given
        let tabID = "test-tab-id"
        let chatViewController = provider.makeChatViewController(for: tabID, burnerMode: .regular)

        // When
        let retrievedViewController = provider.getChatViewController(for: tabID)

        // Then
        XCTAssertNotNil(retrievedViewController)
        XCTAssertIdentical(retrievedViewController, chatViewController)
    }

    func testGetSidebarViewController_withNonExistentTab_returnsNil() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let retrievedViewController = provider.getChatViewController(for: tabID)

        // Then
        XCTAssertNil(retrievedViewController)
    }

    // MARK: - Make Sidebar View Controller Tests

    func testMakeSidebarViewController_createsAndStoresViewController() {
        // Given
        let tabID = "new-tab-id"

        // When
        let chatViewController = provider.makeChatViewController(for: tabID, burnerMode: .regular)

        // Then
        XCTAssertNotNil(chatViewController)
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertNotNil(provider.statesByTab[tabID])
        XCTAssertIdentical(provider.statesByTab[tabID]?.chatViewController, chatViewController)
    }

    func testMakeSidebarViewController_withBurnerMode_createsCorrectViewController() {
        // Given
        let tabID = "burner-tab-id"
        let burnerMode = BurnerMode.burner(websiteDataStore: .nonPersistent())

        // When
        let chatViewController = provider.makeChatViewController(for: tabID, burnerMode: burnerMode)

        // Then
        XCTAssertNotNil(chatViewController)
        XCTAssertNotNil(provider.statesByTab[tabID])
        XCTAssertIdentical(provider.statesByTab[tabID]?.chatViewController, chatViewController)
    }

    func testMakeSidebarViewController_withExistingSidebar_returnsExistingViewController() {
        // Given
        let tabID = "existing-tab"
        let firstViewController = provider.makeChatViewController(for: tabID, burnerMode: .regular)

        // When
        let secondViewController = provider.makeChatViewController(for: tabID, burnerMode: .burner(websiteDataStore: .nonPersistent()))

        // Then
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertIdentical(firstViewController, secondViewController)
        XCTAssertIdentical(provider.statesByTab[tabID]?.chatViewController, firstViewController)
    }

    // MARK: - Is Showing Sidebar Tests

    func testIsShowingSidebar_withRevealedSidebar_returnsTrue() {
        // Given
        let tabID = "test-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        provider.statesByTab[tabID]?.setRevealed()

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertTrue(isShowing)
    }

    func testIsShowingSidebar_withUnrevealedSidebar_returnsFalse() {
        // Given
        let tabID = "test-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        // Note: sidebar starts as not revealed by default

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertFalse(isShowing)
    }

    func testIsShowingSidebar_withNonExistentSidebar_returnsFalse() {
        // Given
        let tabID = "non-existent-tab"

        // When
        let isShowing = provider.isShowingSidebar(for: tabID)

        // Then
        XCTAssertFalse(isShowing)
    }

    // MARK: - Handle Sidebar Did Close Tests

    func testHandleSidebarDidClose_withExistingTab_removesSidebar() {
        // Given
        let tabID = "closing-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        XCTAssertEqual(provider.statesByTab.count, 1)

        // When
        provider.handleSidebarDidClose(for: tabID)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 0)
        XCTAssertNil(provider.statesByTab[tabID])
    }

    func testHandleSidebarDidClose_withNonExistentTab_doesNothing() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        _ = provider.makeChatViewController(for: existingTabID, burnerMode: .regular)
        let initialCount = provider.statesByTab.count

        // When
        provider.handleSidebarDidClose(for: nonExistentTabID)

        // Then
        XCTAssertEqual(provider.statesByTab.count, initialCount)
        XCTAssertNotNil(provider.statesByTab[existingTabID])
    }

    func testHandleSidebarDidClose_withKeepSessionEnabled_preservesSidebarData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "keep-session-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()
        XCTAssertEqual(keepSessionProvider.statesByTab.count, 1)
        XCTAssertTrue(keepSessionProvider.isShowingSidebar(for: tabID))

        // When
        keepSessionProvider.handleSidebarDidClose(for: tabID)

        // Then - sidebar data is preserved but marked as hidden
        XCTAssertEqual(keepSessionProvider.statesByTab.count, 1)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        XCTAssertFalse(keepSessionProvider.isShowingSidebar(for: tabID))
        XCTAssertNil(keepSessionProvider.statesByTab[tabID]?.chatViewController)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID]?.hiddenAt)
    }

    func testHandleSidebarDidClose_withKeepSessionDisabled_removesSidebarData() {
        // Given
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [] // aiChatKeepSession disabled
        let noKeepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "no-keep-session-tab"
        _ = noKeepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        noKeepSessionProvider.statesByTab[tabID]?.setRevealed()
        XCTAssertEqual(noKeepSessionProvider.statesByTab.count, 1)

        // When
        noKeepSessionProvider.handleSidebarDidClose(for: tabID)

        // Then - sidebar data is completely removed
        XCTAssertEqual(noKeepSessionProvider.statesByTab.count, 0)
        XCTAssertNil(noKeepSessionProvider.statesByTab[tabID])
    }

    // MARK: - Clean Up Tests

    func testCleanUp_removesUnneededSidebars() {
        // Given
        _ = provider.makeChatViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeChatViewController(for: "tab2", burnerMode: .regular)
        _ = provider.makeChatViewController(for: "tab3", burnerMode: .regular)
        XCTAssertEqual(provider.statesByTab.count, 3)

        let currentTabIDs = ["tab1", "tab3"] // tab2 should be removed

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 2)
        XCTAssertNotNil(provider.statesByTab["tab1"])
        XCTAssertNil(provider.statesByTab["tab2"])
        XCTAssertNotNil(provider.statesByTab["tab3"])
    }

    func testCleanUp_withEmptyCurrentTabIDs_removesAllSidebars() {
        // Given
        _ = provider.makeChatViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeChatViewController(for: "tab2", burnerMode: .regular)
        XCTAssertEqual(provider.statesByTab.count, 2)

        // When
        provider.cleanUp(for: [])

        // Then
        XCTAssertEqual(provider.statesByTab.count, 0)
        XCTAssertTrue(provider.statesByTab.isEmpty)
    }

    func testCleanUp_withAllCurrentTabs_removesNoSidebars() {
        // Given
        _ = provider.makeChatViewController(for: "tab1", burnerMode: .regular)
        _ = provider.makeChatViewController(for: "tab2", burnerMode: .regular)
        let allTabIDs = ["tab1", "tab2"]
        XCTAssertEqual(provider.statesByTab.count, 2)

        // When
        provider.cleanUp(for: allTabIDs)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 2)
        XCTAssertNotNil(provider.statesByTab["tab1"])
        XCTAssertNotNil(provider.statesByTab["tab2"])
    }

    func testCleanUp_withExtraCurrentTabIDs_doesNotAddSidebars() {
        // Given
        _ = provider.makeChatViewController(for: "tab1", burnerMode: .regular)
        let currentTabIDs = ["tab1", "tab2", "tab3"] // tab2 and tab3 don't exist

        // When
        provider.cleanUp(for: currentTabIDs)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertNotNil(provider.statesByTab["tab1"])
        XCTAssertNil(provider.statesByTab["tab2"])
        XCTAssertNil(provider.statesByTab["tab3"])
    }

    // MARK: - Restore State Tests

    func testRestoreState_clearsExistingState() {
        // Given
        _ = provider.makeChatViewController(for: "existing-tab", burnerMode: .regular)
        XCTAssertEqual(provider.statesByTab.count, 1)

        let newState: AIChatStatesByTab = [:]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertTrue(provider.statesByTab.isEmpty)
    }

    func testRestoreState_setsNewState() {
        // Given
        let newSidebar = AIChatState(burnerMode: .regular)
        let newState: AIChatStatesByTab = ["new-tab": newSidebar]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertIdentical(provider.statesByTab["new-tab"], newSidebar)
    }

    func testRestoreState_replacesCompleteState() {
        // Given
        _ = provider.makeChatViewController(for: "old-tab1", burnerMode: .regular)
        _ = provider.makeChatViewController(for: "old-tab2", burnerMode: .regular)
        XCTAssertEqual(provider.statesByTab.count, 2)

        let newSidebar1 = AIChatState(burnerMode: .regular)
        let newSidebar2 = AIChatState(burnerMode: .burner(websiteDataStore: .nonPersistent()))
        let newState: AIChatStatesByTab = [
            "new-tab1": newSidebar1,
            "new-tab2": newSidebar2
        ]

        // When
        provider.restoreState(newState)

        // Then
        XCTAssertEqual(provider.statesByTab.count, 2)
        XCTAssertNil(provider.statesByTab["old-tab1"])
        XCTAssertNil(provider.statesByTab["old-tab2"])
        XCTAssertIdentical(provider.statesByTab["new-tab1"], newSidebar1)
        XCTAssertIdentical(provider.statesByTab["new-tab2"], newSidebar2)
    }

    // MARK: - Integration Tests

    func testMultipleSidebarOperations() {
        // Given - Create multiple sidebars
        let tab1 = "tab1"
        let tab2 = "tab2"
        let tab3 = "tab3"

        _ = provider.makeChatViewController(for: tab1, burnerMode: .regular)
        _ = provider.makeChatViewController(for: tab2, burnerMode: .burner(websiteDataStore: .nonPersistent()))
        _ = provider.makeChatViewController(for: tab3, burnerMode: .regular)

        // When - Check initial state
        XCTAssertEqual(provider.statesByTab.count, 3)
        XCTAssertNotNil(provider.getChatViewController(for: tab1))
        XCTAssertNotNil(provider.getChatViewController(for: tab2))
        XCTAssertNotNil(provider.getChatViewController(for: tab3))

        // When - Close one sidebar
        provider.handleSidebarDidClose(for: tab2)

        // Then - Verify state after close
        XCTAssertEqual(provider.statesByTab.count, 2)
        XCTAssertNotNil(provider.getChatViewController(for: tab1))
        XCTAssertNil(provider.getChatViewController(for: tab2))
        XCTAssertNotNil(provider.getChatViewController(for: tab3))

        // When - Clean up with only tab1 active
        provider.cleanUp(for: [tab1])

        // Then - Verify final state
        XCTAssertEqual(provider.statesByTab.count, 1)
        XCTAssertNotNil(provider.getChatViewController(for: tab1))
        XCTAssertNil(provider.getChatViewController(for: tab2))
        XCTAssertNil(provider.getChatViewController(for: tab3))
    }

    // MARK: - Session Timeout Tests

    func testMakeSidebarViewController_withExpiredSession_createsNewSidebar() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "session-timeout-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()

        // Simulate the sidebar being hidden and closed
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID]?.hiddenAt)

        // Manually set the hiddenAt to simulate a very old session (more than 60 minutes ago)
        let oldDate = Date().addingTimeInterval(-4000) // ~67 minutes ago, exceeds default 60 minute timeout
        keepSessionProvider.statesByTab[tabID]?.updateHiddenAt(oldDate)

        // When - Create a new view controller (which calls getCurrentSidebar internally)
        let newViewController = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)

        // Then - Should have created a fresh sidebar since the session expired
        XCTAssertNotNil(newViewController)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        // The hiddenAt should be nil for a fresh sidebar
        XCTAssertNil(keepSessionProvider.statesByTab[tabID]?.hiddenAt)
    }

    func testMakeSidebarViewController_withValidSession_returnsExistingSidebar() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "valid-session-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()

        // Simulate the sidebar being hidden and closed recently
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID]?.hiddenAt)

        // Manually set the hiddenAt to simulate a recent session (within timeout)
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago, within default 60 minute timeout
        keepSessionProvider.statesByTab[tabID]?.setHidden(at: recentDate)

        // When - Create a new view controller (which calls getCurrentSidebar internally)
        let newViewController = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)

        // Then - Should reuse the existing sidebar since session is still valid
        XCTAssertNotNil(newViewController)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        // The hiddenAt should still be the recent date (session not expired)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID]?.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetRevealed_updatesIsRevealedState() {
        // Given
        let tabID = "revealed-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        XCTAssertFalse(provider.isShowingSidebar(for: tabID)) // starts as not revealed

        // When
        provider.statesByTab[tabID]?.setRevealed()

        // Then
        XCTAssertTrue(provider.isShowingSidebar(for: tabID))
        XCTAssertNil(provider.statesByTab[tabID]?.hiddenAt) // hiddenAt should be cleared
    }

    func testSetHidden_updatesIsRevealedState() {
        // Given
        let tabID = "hidden-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        provider.statesByTab[tabID]?.setRevealed()
        XCTAssertTrue(provider.isShowingSidebar(for: tabID))

        // When
        provider.statesByTab[tabID]?.setHidden()

        // Then
        XCTAssertFalse(provider.isShowingSidebar(for: tabID))
        XCTAssertNotNil(provider.statesByTab[tabID]?.hiddenAt) // hiddenAt should be set
    }

    // MARK: - Reset Sidebar Tests

    func testWhenResetSidebarCalledThenSidebarIsRemoved() {
        // Given
        let tabID = "reset-test-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        provider.statesByTab[tabID]?.updateRestorationData("test-data")
        XCTAssertNotNil(provider.statesByTab[tabID])

        // When
        provider.resetSidebar(for: tabID)

        // Then - sidebar should be removed from dictionary
        XCTAssertNil(provider.statesByTab[tabID])
        XCTAssertEqual(provider.statesByTab.count, 0)
    }

    func testWhenResetSidebarCalledForNonExistentTabThenNothingHappens() {
        // Given
        let existingTabID = "existing-tab"
        let nonExistentTabID = "non-existent-tab"
        _ = provider.makeChatViewController(for: existingTabID, burnerMode: .regular)
        provider.statesByTab[existingTabID]?.updateRestorationData("test-data")
        let initialCount = provider.statesByTab.count

        // When
        provider.resetSidebar(for: nonExistentTabID)

        // Then - existing tab should be unaffected
        XCTAssertEqual(provider.statesByTab.count, initialCount)
        XCTAssertNotNil(provider.statesByTab[existingTabID]?.restorationData)
    }

    func testWhenResetSidebarCalledThenOtherTabsAreNotAffected() {
        // Given
        let tabID1 = "tab1"
        let tabID2 = "tab2"
        _ = provider.makeChatViewController(for: tabID1, burnerMode: .regular)
        _ = provider.makeChatViewController(for: tabID2, burnerMode: .regular)
        provider.statesByTab[tabID1]?.updateRestorationData("data1")
        provider.statesByTab[tabID2]?.updateRestorationData("data2")

        // When
        provider.resetSidebar(for: tabID1)

        // Then - tab1 should be removed, tab2 should be unaffected
        XCTAssertNil(provider.statesByTab[tabID1])
        XCTAssertNotNil(provider.statesByTab[tabID2])
        XCTAssertEqual(provider.statesByTab[tabID2]?.restorationData, "data2")
    }

    func testWhenResetSidebarCalledBeforeNewHandoffThenFreshSidebarIsCreated() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "fresh-url-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()
        keepSessionProvider.statesByTab[tabID]?.updateRestorationData("old-chat-data")

        // Simulate closing the sidebar
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])

        // When - Reset before creating new sidebar (simulating new handoff)
        keepSessionProvider.resetSidebar(for: tabID)
        XCTAssertNil(keepSessionProvider.statesByTab[tabID]) // Sidebar was removed

        // Creating new sidebar should create a fresh one
        let newViewController = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)

        // Then - Should have a fresh sidebar without restoration data
        XCTAssertNotNil(newViewController)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
        XCTAssertNil(keepSessionProvider.statesByTab[tabID]?.restorationData)
    }

    // MARK: - Clear Sidebar If Session Expired Tests

    func testClearSidebarIfSessionExpired_withExpiredSession_clearsSidebarAndReturnsTrue() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "expired-session-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()

        // Simulate closing and set hiddenAt to 70 minutes ago (exceeds 60 minute timeout)
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        keepSessionProvider.statesByTab[tabID]?.updateHiddenAt(oldDate)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])

        // When
        let wasCleared = keepSessionProvider.clearSidebarIfSessionExpired(for: tabID)

        // Then
        XCTAssertTrue(wasCleared)
        XCTAssertNil(keepSessionProvider.statesByTab[tabID])
    }

    func testClearSidebarIfSessionExpired_withValidSession_doesNotClearAndReturnsFalse() {
        // Given - Create provider with keep session enabled
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.aiChatKeepSession]
        let keepSessionProvider = AIChatStateProvider(featureFlagger: mockFeatureFlagger)

        let tabID = "valid-session-tab"
        _ = keepSessionProvider.makeChatViewController(for: tabID, burnerMode: .regular)
        keepSessionProvider.statesByTab[tabID]?.setRevealed()

        // Simulate closing and set hiddenAt to 30 minutes ago (within 60 minute timeout)
        keepSessionProvider.handleSidebarDidClose(for: tabID)
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago
        keepSessionProvider.statesByTab[tabID]?.updateHiddenAt(recentDate)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])

        // When
        let wasCleared = keepSessionProvider.clearSidebarIfSessionExpired(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
        XCTAssertNotNil(keepSessionProvider.statesByTab[tabID])
    }

    func testClearSidebarIfSessionExpired_withNoSidebar_returnsFalse() {
        // Given
        let tabID = "non-existent-tab"
        XCTAssertNil(provider.statesByTab[tabID])

        // When
        let wasCleared = provider.clearSidebarIfSessionExpired(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
    }

    func testClearSidebarIfSessionExpired_withNilHiddenAt_returnsFalse() {
        // Given - Sidebar that was never hidden (hiddenAt is nil)
        let tabID = "never-hidden-tab"
        _ = provider.makeChatViewController(for: tabID, burnerMode: .regular)
        provider.statesByTab[tabID]?.setRevealed()
        XCTAssertNil(provider.statesByTab[tabID]?.hiddenAt)

        // When
        let wasCleared = provider.clearSidebarIfSessionExpired(for: tabID)

        // Then
        XCTAssertFalse(wasCleared)
        XCTAssertNotNil(provider.statesByTab[tabID])
    }

}
