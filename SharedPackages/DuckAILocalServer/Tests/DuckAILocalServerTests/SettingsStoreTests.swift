//
//  SettingsStoreTests.swift
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
@testable import DuckAILocalServerImpl

final class SettingsStoreTests: XCTestCase {
    private var sut: UserDefaultsDuckAISettingsStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.duckai.settings")!
        defaults.removePersistentDomain(forName: "test.duckai.settings")
        sut = UserDefaultsDuckAISettingsStore(userDefaults: defaults)
    }

    func testGetAllReturnsEmptyDictionaryByDefault() {
        XCTAssertEqual(sut.getAll(), [:])
    }

    func testSetAndGetSingleKey() {
        sut.set(key: "theme", value: "dark")
        XCTAssertEqual(sut.get(key: "theme"), "dark")
    }

    func testGetMissingKeyReturnsNil() {
        XCTAssertNil(sut.get(key: "missing"))
    }

    func testReplaceAllOverwritesExisting() {
        sut.set(key: "old", value: "value")
        sut.replaceAll(settings: ["new": "value"])
        XCTAssertNil(sut.get(key: "old"))
        XCTAssertEqual(sut.get(key: "new"), "value")
    }

    func testDeleteRemovesKey() {
        sut.set(key: "theme", value: "dark")
        sut.delete(key: "theme")
        XCTAssertNil(sut.get(key: "theme"))
    }

    func testDeleteAllClearsEverything() {
        sut.set(key: "a", value: "1")
        sut.set(key: "b", value: "2")
        sut.deleteAll()
        XCTAssertEqual(sut.getAll(), [:])
    }

    func testMigrationDoneDefaultsToFalse() {
        XCTAssertFalse(sut.isMigrationDone)
    }

    func testSetMigrationDone() {
        sut.setMigrationDone()
        XCTAssertTrue(sut.isMigrationDone)
    }
}
