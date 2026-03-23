//
//  MigrationHandlerTests.swift
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
import DuckAILocalServerAPI

final class MigrationHandlerTests: XCTestCase {
    private var store: MockSettingsStore!
    private var sut: MigrationHandler!

    override func setUp() {
        super.setUp()
        store = MockSettingsStore()
        sut = MigrationHandler(store: store)
    }

    func testPathPrefix() {
        XCTAssertEqual(sut.pathPrefix, "/migration")
    }

    func testGetMigrationNotDone() async {
        let response = await sut.handle(method: "GET", uri: "/migration", body: nil)
        XCTAssertEqual(response.statusCode, 200)
        let json = try! JSONSerialization.jsonObject(with: response.body!) as! [String: Bool]
        XCTAssertEqual(json, ["done": false])
    }

    func testPostMarksMigrationDone() async {
        let response = await sut.handle(method: "POST", uri: "/migration", body: nil)
        XCTAssertEqual(response.statusCode, 204)
        XCTAssertTrue(store.migrationDone)
    }

    func testGetAfterPostReturnsDone() async {
        _ = await sut.handle(method: "POST", uri: "/migration", body: nil)
        let response = await sut.handle(method: "GET", uri: "/migration", body: nil)
        let json = try! JSONSerialization.jsonObject(with: response.body!) as! [String: Bool]
        XCTAssertEqual(json, ["done": true])
    }

    func testUnsupportedMethodReturns405() async {
        let response = await sut.handle(method: "DELETE", uri: "/migration", body: nil)
        XCTAssertEqual(response.statusCode, 405)
    }
}
