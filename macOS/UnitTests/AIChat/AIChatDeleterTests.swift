//
//  AIChatDeleterTests.swift
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
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatDeleterTests: XCTestCase {

    private var historyCleaner: MockPhasedHistoryCleaner!
    private var syncCleaner: MockAIChatDeleterSyncCleaner!
    private var firedPixels: [String]!

    override func setUp() {
        super.setUp()
        historyCleaner = MockPhasedHistoryCleaner()
        syncCleaner = MockAIChatDeleterSyncCleaner()
        firedPixels = []
    }

    private func makeSUT(recordsSyncDeletion: Bool = true) -> AIChatDeleter {
        AIChatDeleter(
            historyCleaner: historyCleaner,
            syncCleaner: { [weak self] in self?.syncCleaner },
            recordsSyncDeletion: recordsSyncDeletion,
            firePixel: { [weak self] event in self?.firedPixels.append(event.name) }
        )
    }

    func testWhenNativeAndJSClearSucceedThenSyncDeletionIsRecordedAndScheduled() async {
        historyCleaner.nativeStorageResult = .success(())
        historyCleaner.jsDataResult = .success(())
        let sut = makeSUT()

        sut.deleteChat(chatID: "chat-1")
        await historyCleaner.waitForClearJSData()

        XCTAssertEqual(syncCleaner.recordChatDeletionCalls, ["chat-1"])
        XCTAssertEqual(syncCleaner.scheduleSyncCallCount, 1)
        XCTAssertEqual(firedPixels, [AIChatPixel.aiChatSingleDeleteSuccessful.name])
    }

    func testWhenJSClearFailsThenSyncDeletionIsNotRecorded() async {
        historyCleaner.nativeStorageResult = .success(())
        historyCleaner.jsDataResult = .failure(TestError())
        let sut = makeSUT()

        sut.deleteChat(chatID: "chat-1")
        await historyCleaner.waitForClearJSData()

        XCTAssertTrue(syncCleaner.recordChatDeletionCalls.isEmpty)
        XCTAssertEqual(syncCleaner.scheduleSyncCallCount, 0)
        XCTAssertEqual(firedPixels, [AIChatPixel.aiChatSingleDeleteFailed.name])
    }

    func testWhenNativeStorageUnavailableAndJSClearSucceedsThenSyncDeletionIsRecorded() async {
        // nil means native storage isn't enabled/migrated yet — not a failure.
        historyCleaner.nativeStorageResult = nil
        historyCleaner.jsDataResult = .success(())
        let sut = makeSUT()

        sut.deleteChat(chatID: "chat-1")
        await historyCleaner.waitForClearJSData()

        XCTAssertEqual(syncCleaner.recordChatDeletionCalls, ["chat-1"])
        XCTAssertEqual(firedPixels, [AIChatPixel.aiChatSingleDeleteSuccessful.name])
    }

    func testWhenNativeStorageFailsThenOverallResultIsFailureRegardlessOfJSClear() async {
        historyCleaner.nativeStorageResult = .failure(TestError())
        historyCleaner.jsDataResult = .success(())
        let sut = makeSUT()

        sut.deleteChat(chatID: "chat-1")
        await historyCleaner.waitForClearJSData()

        XCTAssertTrue(syncCleaner.recordChatDeletionCalls.isEmpty)
        XCTAssertEqual(firedPixels, [AIChatPixel.aiChatSingleDeleteFailed.name])
    }

    func testWhenRecordsSyncDeletionIsFalseThenSyncIsNeverRecordedEvenOnSuccess() async {
        historyCleaner.nativeStorageResult = .success(())
        historyCleaner.jsDataResult = .success(())
        let sut = makeSUT(recordsSyncDeletion: false)

        sut.deleteChat(chatID: "chat-1")
        await historyCleaner.waitForClearJSData()

        XCTAssertTrue(syncCleaner.recordChatDeletionCalls.isEmpty)
        XCTAssertEqual(syncCleaner.scheduleSyncCallCount, 0)
    }

    func testDeleteChatReturnsBeforeJSClearCompletes() {
        historyCleaner.nativeStorageResult = .success(())
        historyCleaner.jsDataResult = .success(())
        historyCleaner.holdClearJSData = true
        let sut = makeSUT()

        sut.deleteChat(chatID: "chat-1")

        // deleteChat has returned synchronously, but clearJSData is still being held open —
        // the native-storage phase must have already run.
        XCTAssertEqual(historyCleaner.deleteAIChatFromNativeStorageCalls, ["chat-1"])
        XCTAssertTrue(syncCleaner.recordChatDeletionCalls.isEmpty)

        historyCleaner.releaseClearJSData()
    }

}

private struct TestError: Error {}

private final class MockPhasedHistoryCleaner: PhasedAIChatHistoryCleaning {
    var nativeStorageResult: Result<Void, Error>? = .success(())
    var jsDataResult: Result<Void, Error> = .success(())
    var holdClearJSData = false

    private(set) var deleteAIChatFromNativeStorageCalls: [String] = []
    private(set) var clearJSDataCalls: [String?] = []

    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var clearJSDataCalledContinuation: CheckedContinuation<Void, Never>?

    @MainActor
    func deleteAIChatFromNativeStorage(chatID: String) -> Result<Void, Error>? {
        deleteAIChatFromNativeStorageCalls.append(chatID)
        return nativeStorageResult
    }

    @MainActor
    func clearJSData(chatID: String?) async -> Result<Void, Error> {
        clearJSDataCalls.append(chatID)
        clearJSDataCalledContinuation?.resume()
        clearJSDataCalledContinuation = nil
        if holdClearJSData {
            await withCheckedContinuation { self.releaseContinuation = $0 }
        }
        return jsDataResult
    }

    /// Waits until `clearJSData` has been invoked and returned, so tests can assert on
    /// post-Task-completion state without an arbitrary sleep.
    func waitForClearJSData() async {
        await withCheckedContinuation { continuation in
            if !clearJSDataCalls.isEmpty {
                continuation.resume()
            } else {
                clearJSDataCalledContinuation = continuation
            }
        }
    }

    func releaseClearJSData() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    @MainActor
    func cleanAIChatHistory() async -> Result<Void, Error> { .success(()) }

    @MainActor
    func deleteAIChat(chatID: String) async -> Result<Void, Error> { .success(()) }
}

private final class MockAIChatDeleterSyncCleaner: AIChatSyncCleaning {
    private(set) var recordChatDeletionCalls: [String] = []
    private(set) var scheduleSyncCallCount = 0

    func recordAutoClearBackgroundTimestamp(date: Date?) async {}
    func recordLocalClear(date: Date?) async {}
    func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async {}

    func recordChatDeletion(chatID: String) async {
        recordChatDeletionCalls.append(chatID)
    }

    func deleteIfNeeded() async {}
    func recordChatUpdate(chatID: String) async {}
    func updateIfNeeded() async {}

    func scheduleSync() {
        scheduleSyncCallCount += 1
    }
}
