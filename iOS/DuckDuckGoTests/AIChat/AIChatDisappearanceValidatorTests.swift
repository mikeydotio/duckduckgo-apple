//
//  AIChatDisappearanceValidatorTests.swift
//  DuckDuckGo
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

import XCTest
import AIChat
import Core
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
final class AIChatDisappearanceValidatorTests: XCTestCase {

    private var mockStorage: MockThrowingKeyValueStore!
    private var mockReader: MockSuggestionsReader!

    override func setUp() {
        super.setUp()
        mockStorage = MockThrowingKeyValueStore()
        mockReader = MockSuggestionsReader()
        PixelFiringMock.tearDown()
    }

    override func tearDown() {
        mockStorage = nil
        mockReader = nil
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    // MARK: - saveChatSnapshot

    func testWhenSaveChatSnapshotCalledThenCountAndTimestampArePersisted() async {
        // Given
        mockReader.resultToReturn = .success((pinned: makeSuggestions(count: 2), recent: makeSuggestions(count: 3)))
        let sut = makeValidator()

        // When
        await sut.saveChatSnapshot()

        // Then
        let savedCount = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedChatCount) as? Int
        let savedTimestamp = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedTimestamp) as? Double
        XCTAssertEqual(savedCount, 5)
        XCTAssertNotNil(savedTimestamp)
        XCTAssertTrue(mockReader.tearDownCalled)
    }

    func testWhenSaveChatSnapshotCalledWithZeroChatsThenZeroIsPersisted() async {
        // Given
        mockReader.resultToReturn = .success((pinned: [], recent: []))
        let sut = makeValidator()

        // When
        await sut.saveChatSnapshot()

        // Then
        let savedCount = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedChatCount) as? Int
        XCTAssertEqual(savedCount, 0)
    }

    func testWhenSaveChatSnapshotFailsThenNothingIsPersisted() async {
        // Given
        mockReader.resultToReturn = .failure(NSError(domain: "test", code: 1))
        let sut = makeValidator()

        // When
        await sut.saveChatSnapshot()

        // Then
        let savedCount = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        XCTAssertNil(savedCount)
        XCTAssertTrue(mockReader.tearDownCalled)
    }

    // MARK: - checkForUnexpectedDeletion

    func testWhenNoSavedSnapshotThenCheckDoesNothing() async {
        // Given
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertEqual(mockReader.fetchSuggestionsCallCount, 0)
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenLessThanSevenDaysPassedThenCheckDoesNothing() async {
        // Given
        let sixDaysAgo = Date().timeIntervalSince1970 - (6 * 24 * 60 * 60)
        try? mockStorage.set(10, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(sixDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertEqual(mockReader.fetchSuggestionsCallCount, 0)
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenSevenDaysPassedAndChatsDecreasedThenPixelIsFired() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(10, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: [], recent: makeSuggestions(count: 3)))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatChatsDisappearedAfterWeek.name)
    }

    func testWhenSevenDaysPassedAndChatCountSameThenPixelIsNotFired() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(5, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: makeSuggestions(count: 2), recent: makeSuggestions(count: 3)))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenSevenDaysPassedAndChatCountIncreasedThenPixelIsNotFired() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(3, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: makeSuggestions(count: 2), recent: makeSuggestions(count: 5)))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenSevenDaysPassedAndSavedCountIsZeroThenPixelIsNotFired() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(0, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertEqual(mockReader.fetchSuggestionsCallCount, 0)
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenCheckCompletedThenSnapshotIsCleared() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(10, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: [], recent: []))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        let savedCount = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        let savedTimestamp = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        XCTAssertNil(savedCount)
        XCTAssertNil(savedTimestamp)
    }

    func testWhenCheckCompletedWithFetchFailureThenSnapshotIsCleared() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(10, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .failure(NSError(domain: "test", code: 1))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        let savedCount = try? mockStorage.object(forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        XCTAssertNil(savedCount)
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    func testWhenExactlySevenDaysPassedThenCheckRuns() async {
        // Given
        let exactlySevenDaysAgo = Date().timeIntervalSince1970 - AIChatDisappearanceValidator.sevenDaysInSeconds
        try? mockStorage.set(10, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(exactlySevenDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: [], recent: makeSuggestions(count: 5)))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.aiChatChatsDisappearedAfterWeek.name)
    }

    func testWhenReaderTearDownCalledAfterCheck() async {
        // Given
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        try? mockStorage.set(5, forKey: AIChatDisappearanceValidator.Keys.savedChatCount)
        try? mockStorage.set(eightDaysAgo, forKey: AIChatDisappearanceValidator.Keys.savedTimestamp)
        mockReader.resultToReturn = .success((pinned: [], recent: makeSuggestions(count: 5)))
        let sut = makeValidator()

        // When
        await sut.checkForUnexpectedDeletion()

        // Then
        XCTAssertTrue(mockReader.tearDownCalled)
    }

    // MARK: - Helpers

    private func makeValidator() -> AIChatDisappearanceValidator {
        AIChatDisappearanceValidator(
            storage: mockStorage,
            suggestionsReaderProvider: { [mockReader] in mockReader! },
            pixelFiring: PixelFiringMock.self
        )
    }

    private func makeSuggestions(count: Int) -> [AIChatSuggestion] {
        (0..<count).map { index in
            AIChatSuggestion(
                id: "test-\(index)",
                title: "Chat \(index)",
                isPinned: false,
                chatId: "chat-\(index)"
            )
        }
    }
}

// MARK: - MockSuggestionsReader

@MainActor
private final class MockSuggestionsReader: SuggestionsReading {
    var resultToReturn: Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error> = .success((pinned: [], recent: []))
    var fetchSuggestionsCallCount = 0
    var tearDownCalled = false

    func fetchSuggestions(query: String?, maxChats: Int) async -> Result<(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]), Error> {
        fetchSuggestionsCallCount += 1
        return resultToReturn
    }

    func tearDown() {
        tearDownCalled = true
    }
}
