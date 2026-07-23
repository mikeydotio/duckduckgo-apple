//
//  TabsModelPersistenceTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Persistence
@testable import DuckDuckGo
@testable import Core
@testable import PersistenceTestingUtils

class TabsModelPersistenceTests: XCTestCase {

    struct Constants {
        static let firstTitle = "a title"
        static let firstUrl = "http://example.com"
        static let secondTitle = "another title"
        static let secondUrl = "http://anotherurl.com"
    }

    var mockNormalStore: ThrowingKeyValueStoring!
    var mockFireStore: ThrowingKeyValueStoring!
    var mockLegacyStore: KeyValueStoring!
    var persistence: TabsModelPersisting!
    private var firstTab: Tab!
    private var secondTab: Tab!

    override func setUp() async throws {
        try await super.setUp()

        let normalStore = try MockKeyValueFileStore(throwOnInit: nil)
        let fireStore = try MockKeyValueFileStore(throwOnInit: nil)
        let legacyStore = MockKeyValueStore()
        mockNormalStore = normalStore
        mockFireStore = fireStore
        mockLegacyStore = legacyStore
        firstTab = tab(title: Constants.firstTitle, url: Constants.firstUrl)
        secondTab = tab(title: Constants.firstTitle, url: Constants.firstUrl)

        persistence = TabsModelPersistence(normalStore: normalStore,
                                           fireStore: fireStore,
                                           legacyStore: legacyStore)

        setupUserDefault(with: #file)
        UserDefaults.app.removeObject(forKey: "com.duckduckgo.opentabs")
    }

    private func tab(title: String, url: String) -> Tab {
        return Tab(link: Link(title: title, url: URL(string: url)!))
    }

    private var model: TabsModel {
        let model = TabsModel(tabs: [
            firstTab,
            secondTab
        ], desktop: UIDevice.current.userInterfaceIdiom == .pad)
        return model
    }

    // MARK: - Normal Key Tests

    func testBeforeModelSavedThenGetIsNil() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenModelSavedThenGetIsNotNil() throws {
        _ = persistence.saveSynchronously(model: model, for: .normal)
        XCTAssertNotNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenModelIsSavedThenGetLoadsCompleteTabs() throws {
        _ = persistence.saveSynchronously(model: model, for: .normal)

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.get(tabAt: 0), firstTab)
        XCTAssertEqual(loaded?.get(tabAt: 1), secondTab)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenModelIsSavedThenGetLoadsModelWithCurrentSelection() throws {
        let model = self.model
        model.select(tab: model.tabs[1])
        _ = persistence.saveSynchronously(model: model, for: .normal)

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 1)
    }

    func testWhenMigratingEmptyNoModelIsReturned() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .normal))
    }

    func testWhenMigratingExistingItIsReturnedAndCleared() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    func testWhenNotMigratingThenOldValueIsIgnoredIfPresent() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let newData = try NSKeyedArchiver.archivedData(withRootObject: TabsModel(desktop: false), requiringSecureCoding: false)
        try mockNormalStore.set(newData, forKey: "TabsModelKey")

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.currentIndex, 0)
    }

    // MARK: - Fire Key Tests

    func testWhenFireModelNotSavedThenGetReturnsNil() throws {
        XCTAssertNil(try persistence.getTabsModel(for: .fire))
    }

    func testWhenFireModelSavedThenGetReturnsModel() throws {
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.saveSynchronously(model: fireModel, for: .fire)

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
    }

    func testWhenFireModelSavedThenGetLoadsWithFireMode() throws {
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.saveSynchronously(model: fireModel, for: .fire)

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertEqual(loaded?.mode, .fire)
    }

    func testWhenClearAllThenBothKeysCleared() throws {
        _ = persistence.saveSynchronously(model: model, for: .normal)
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.saveSynchronously(model: fireModel, for: .fire)

        persistence.clearAll()

        XCTAssertNil(try persistence.getTabsModel(for: .normal))
        XCTAssertNil(try persistence.getTabsModel(for: .fire))
    }

    func testWhenClearNormalThenFireModelUntouched() throws {
        _ = persistence.saveSynchronously(model: model, for: .normal)
        let fireModel = TabsModel(tabs: [firstTab], desktop: false, mode: .fire)
        _ = persistence.saveSynchronously(model: fireModel, for: .fire)

        persistence.clear(for: .normal)

        XCTAssertNil(try persistence.getTabsModel(for: .normal))
        XCTAssertNotNil(try persistence.getTabsModel(for: .fire))
    }

    func testLegacyMigrationDoesNotRunForFireKey() throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel(for: .fire)
        XCTAssertNil(loaded)
    }

    // MARK: - Async save + flush

    func testSave_returnsSuccessImmediately() throws {
        // The async path returns `.success` without waiting for the disk write.
        let result = persistence.save(model: model, for: .normal)
        if case .failure = result {
            XCTFail("save should return success immediately")
        }
    }

    func testFlush_blocksUntilPendingWriteCompletes() throws {
        let countingStore = CountingThrowingKeyValueStore()
        let persistence = TabsModelPersistence(normalStore: countingStore,
                                               fireStore: try MockKeyValueFileStore(throwOnInit: nil),
                                               legacyStore: MockKeyValueStore())
        _ = persistence.save(model: model, for: .normal)
        persistence.flush()
        XCTAssertEqual(countingStore.setCount, 1, "flush should have waited for the queued write")
    }

    func testSaveSynchronously_propagatesStoreError() throws {
        let throwingStore = try MockKeyValueFileStore(throwOnInit: nil)
        throwingStore.shouldThrowOnSet = true
        let persistence = TabsModelPersistence(normalStore: throwingStore,
                                               fireStore: try MockKeyValueFileStore(throwOnInit: nil),
                                               legacyStore: MockKeyValueStore())
        let result = persistence.saveSynchronously(model: model, for: .normal)
        if case .success = result {
            XCTFail("saveSynchronously should propagate store error")
        }
    }

    // MARK: - Secondary scene (allowsLegacyMigration = false)

    func testWhenLegacyMigrationDisallowed_existingLegacyDataIsNotMigrated() throws {
        let legacyStore = MockKeyValueStore()
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        legacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let secondaryPersistence = TabsModelPersistence(normalStore: try MockKeyValueFileStore(throwOnInit: nil),
                                                        fireStore: try MockKeyValueFileStore(throwOnInit: nil),
                                                        legacyStore: legacyStore,
                                                        allowsLegacyMigration: false)

        XCTAssertNil(try secondaryPersistence.getTabsModel(for: .normal))
        // The legacy key must be left untouched for the primary scene to migrate later.
        XCTAssertNotNil(legacyStore.object(forKey: "com.duckduckgo.opentabs"))
    }

    func testWhenLegacyMigrationDisallowed_clearAllDoesNotTouchLegacyStore() throws {
        let legacyStore = MockKeyValueStore()
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        legacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let secondaryPersistence = TabsModelPersistence(normalStore: try MockKeyValueFileStore(throwOnInit: nil),
                                                        fireStore: try MockKeyValueFileStore(throwOnInit: nil),
                                                        legacyStore: legacyStore,
                                                        allowsLegacyMigration: false)
        secondaryPersistence.clearAll()

        XCTAssertNotNil(legacyStore.object(forKey: "com.duckduckgo.opentabs"))
    }

    // MARK: - deleteFiles(forDiscardedSceneID:)

    private final class RedirectingFileManager: FileManager {
        let redirectedDirectory: URL
        init(redirectedDirectory: URL) {
            self.redirectedDirectory = redirectedDirectory
            super.init()
        }
        override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
            [redirectedDirectory]
        }
    }

    func testDeleteFilesForDiscardedSceneID_removesBothTabFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sceneID = "discarded-scene-123"
        let normalFile = tempDir.appendingPathComponent("TabsModel-\(sceneID)")
        let fireFile = tempDir.appendingPathComponent("FireTabsModel-\(sceneID)")
        try Data().write(to: normalFile)
        try Data().write(to: fireFile)

        TabsModelPersistence.deleteFiles(forDiscardedSceneID: sceneID, fileManager: RedirectingFileManager(redirectedDirectory: tempDir))

        XCTAssertFalse(FileManager.default.fileExists(atPath: normalFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fireFile.path))
    }

    func testDeleteFilesForDiscardedSceneID_leavesOtherScenesFilesUntouched() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherFile = tempDir.appendingPathComponent("TabsModel-still-open-scene")
        try Data().write(to: otherFile)

        TabsModelPersistence.deleteFiles(forDiscardedSceneID: "discarded-scene-123",
                                         fileManager: RedirectingFileManager(redirectedDirectory: tempDir))

        XCTAssertTrue(FileManager.default.fileExists(atPath: otherFile.path))
    }

    func testDeleteFilesForDiscardedSceneID_noFilesPresent_doesNotThrowOrCrash() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Deliberately not created — deleteFiles must tolerate a missing directory/files.
        TabsModelPersistence.deleteFiles(forDiscardedSceneID: "never-existed",
                                         fileManager: RedirectingFileManager(redirectedDirectory: tempDir))
    }

    func testAllowsLegacyMigrationDefaultsToTrue() throws {
        // The designated initializer must default to `true` so every existing call site
        // (primary-scene production code, and every test above) keeps today's behavior unchanged.
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        mockLegacyStore.set(data, forKey: "com.duckduckgo.opentabs")

        let loaded = try persistence.getTabsModel(for: .normal)
        XCTAssertNotNil(loaded)
    }

}

/// Counts `set` calls so tests can assert how many disk writes actually landed.
private final class CountingThrowingKeyValueStore: ThrowingKeyValueStoring, @unchecked Sendable {
    private(set) var setCount = 0
    private(set) var storedValue: Any?
    private let lock = NSLock()

    func object(forKey defaultName: String) throws -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
        lock.lock()
        setCount += 1
        storedValue = value
        lock.unlock()
    }

    func removeObject(forKey defaultName: String) throws {
        lock.lock()
        storedValue = nil
        lock.unlock()
    }
}
