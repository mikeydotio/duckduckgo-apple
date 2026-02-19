//
//  AIChatStateTests.swift
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

import XCTest
import Combine
import AIChat
@testable import DuckDuckGo_Privacy_Browser

final class AIChatStateTests: XCTestCase {

    var chatState: AIChatState!

    override func setUp() {
        super.setUp()
        chatState = AIChatState(burnerMode: .regular)
    }

    override func tearDown() {
        chatState = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_setsDefaultProperties() {
        // Given & When
        let chatState = AIChatState(burnerMode: .regular)

        // Then
        XCTAssertNil(chatState.restorationData)
        XCTAssertEqual(chatState.presentationMode, .hidden)
        XCTAssertFalse(chatState.isPresented)
        XCTAssertFalse(chatState.isDetached)
        XCTAssertNil(chatState.hiddenAt)
        XCTAssertNil(chatState.chatViewController)
    }

    // MARK: - Persist State and Reset Tests

    func testPersistStateAndReset_withPersistingState_clearsViewController() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        chatState.chatViewController = viewController
        XCTAssertNotNil(chatState.chatViewController)

        // When
        chatState.persistStateAndReset(persistingState: true)

        // Then
        XCTAssertNil(chatState.chatViewController)
        XCTAssertFalse(chatState.isPresented)
        XCTAssertNotNil(chatState.hiddenAt)
    }

    func testPersistStateAndReset_withoutPersistingState_clearsViewController() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        chatState.chatViewController = viewController
        XCTAssertNotNil(chatState.chatViewController)

        // When
        chatState.persistStateAndReset(persistingState: false)

        // Then
        XCTAssertNil(chatState.chatViewController)
        XCTAssertFalse(chatState.isPresented)
        XCTAssertNotNil(chatState.hiddenAt)
    }

    func testPersistStateAndReset_setsHiddenState() {
        // Given
        let aiChatRemoteSettings = AIChatRemoteSettings()
        let initialAIChatURL = aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        let viewController = AIChatViewController(currentAIChatURL: initialAIChatURL, burnerMode: .regular)
        chatState.chatViewController = viewController
        chatState.setRevealed()
        XCTAssertTrue(chatState.isPresented)
        XCTAssertNil(chatState.hiddenAt)

        // When
        chatState.persistStateAndReset(persistingState: true)

        // Then
        XCTAssertFalse(chatState.isPresented)
        XCTAssertNotNil(chatState.hiddenAt)
    }

    // MARK: - State Management Tests

    func testSetRevealed_clearsHiddenAt() {
        // Given
        chatState.setHidden()
        XCTAssertNotNil(chatState.hiddenAt)

        // When
        chatState.setRevealed()

        // Then
        XCTAssertTrue(chatState.isPresented)
        XCTAssertNil(chatState.hiddenAt)
    }

    func testSetHidden_setsHiddenAt() {
        // Given
        chatState.setRevealed()
        XCTAssertTrue(chatState.isPresented)
        XCTAssertNil(chatState.hiddenAt)

        // When
        chatState.setHidden()

        // Then
        XCTAssertFalse(chatState.isPresented)
        XCTAssertNotNil(chatState.hiddenAt)
    }

    // MARK: - Session Expiry Tests

    func testIsSessionExpired_withNilHiddenAt_returnsFalse() {
        // Given - sidebar starts with nil hiddenAt
        XCTAssertNil(chatState.hiddenAt)

        // When & Then
        XCTAssertFalse(chatState.isSessionExpired)
    }

    func testIsSessionExpired_withRecentHiddenAt_returnsFalse() {
        // Given - sidebar hidden 30 minutes ago (within default 60 minute timeout)
        let recentDate = Date().addingTimeInterval(-1800) // 30 minutes ago
        chatState.updateHiddenAt(recentDate)

        // When & Then
        XCTAssertFalse(chatState.isSessionExpired)
    }

    func testIsSessionExpired_withOldHiddenAt_returnsTrue() {
        // Given - sidebar hidden 70 minutes ago (exceeds default 60 minute timeout)
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        chatState.updateHiddenAt(oldDate)

        // When & Then
        XCTAssertTrue(chatState.isSessionExpired)
    }

    func testIsSessionExpired_afterSetRevealed_returnsFalse() {
        // Given - sidebar was hidden long ago
        let oldDate = Date().addingTimeInterval(-4200) // 70 minutes ago
        chatState.updateHiddenAt(oldDate)
        XCTAssertTrue(chatState.isSessionExpired)

        // When - sidebar is revealed
        chatState.setRevealed()

        // Then - session is no longer expired (hiddenAt is cleared)
        XCTAssertFalse(chatState.isSessionExpired)
    }

    // MARK: - Presentation Mode Transition Tests

    func testSetRevealed_setsPresentationModeToSidebar() {
        chatState.setRevealed()
        XCTAssertEqual(chatState.presentationMode, .sidebar)
        XCTAssertTrue(chatState.isPresented)
        XCTAssertFalse(chatState.isDetached)
    }

    func testSetDetached_setsPresentationModeToFloating() {
        chatState.setDetached()
        XCTAssertEqual(chatState.presentationMode, .floating)
        XCTAssertTrue(chatState.isPresented)
        XCTAssertTrue(chatState.isDetached)
    }

    func testSetDocked_setsPresentationModeToSidebar() {
        chatState.setDetached()
        XCTAssertEqual(chatState.presentationMode, .floating)

        chatState.setDocked()
        XCTAssertEqual(chatState.presentationMode, .sidebar)
        XCTAssertFalse(chatState.isDetached)
    }

    func testSetHidden_setsPresentationModeToHidden() {
        chatState.setRevealed()
        XCTAssertEqual(chatState.presentationMode, .sidebar)

        chatState.setHidden()
        XCTAssertEqual(chatState.presentationMode, .hidden)
        XCTAssertFalse(chatState.isPresented)
        XCTAssertFalse(chatState.isDetached)
    }

    func testPersistStateAndReset_setsPresentationModeToHidden() {
        chatState.setDetached()
        XCTAssertEqual(chatState.presentationMode, .floating)

        chatState.persistStateAndReset(persistingState: false)
        XCTAssertEqual(chatState.presentationMode, .hidden)
    }

    // MARK: - NSSecureCoding Round-Trip Tests

    func testNSSecureCoding_roundTrip_preservesPresentationMode() {
        // Given
        chatState.setDetached()
        chatState.sidebarWidth = 450

        // When -- encode and decode
        let data = try! NSKeyedArchiver.archivedData(withRootObject: chatState!, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .floating)
        XCTAssertTrue(decoded.isPresented)
        XCTAssertTrue(decoded.isDetached)
        XCTAssertEqual(decoded.sidebarWidth, 450)
    }

    func testNSSecureCoding_legacyFormat_migratesBoolsToEnum() {
        // Given -- encode using the old two-bool key names
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(true, forKey: AIChatState.CodingKeys.isPresented)
        archiver.encode(true, forKey: AIChatState.CodingKeys.isDetached)
        archiver.finishEncoding()
        let data = archiver.encodedData

        // When
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then -- legacy bools should map to .floating
        XCTAssertEqual(decoded.presentationMode, .floating)
        XCTAssertTrue(decoded.isPresented)
        XCTAssertTrue(decoded.isDetached)
    }

    func testNSSecureCoding_legacyFormat_hiddenState() {
        // Given -- encode hidden state using old format
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(false, forKey: AIChatState.CodingKeys.isPresented)
        archiver.encode(false, forKey: AIChatState.CodingKeys.isDetached)
        archiver.finishEncoding()
        let data = archiver.encodedData

        // When
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .hidden)
        XCTAssertFalse(decoded.isPresented)
    }

    func testNSSecureCoding_legacyFormat_sidebarState() {
        // Given -- encode sidebar state using old format
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let url = AIChatRemoteSettings().aiChatURL.forAIChatSidebar()
        archiver.encode(url as NSURL, forKey: AIChatState.CodingKeys.initialAIChatURL)
        archiver.encode(true, forKey: AIChatState.CodingKeys.isPresented)
        archiver.encode(false, forKey: AIChatState.CodingKeys.isDetached)
        archiver.finishEncoding()
        let data = archiver.encodedData

        // When
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: AIChatState.self, from: data)!

        // Then
        XCTAssertEqual(decoded.presentationMode, .sidebar)
        XCTAssertTrue(decoded.isPresented)
        XCTAssertFalse(decoded.isDetached)
    }
}
