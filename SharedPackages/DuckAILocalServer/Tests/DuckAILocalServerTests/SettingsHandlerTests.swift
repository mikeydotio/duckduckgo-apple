//
//  SettingsHandlerTests.swift
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

final class SettingsHandlerTests: XCTestCase {

    private var store: MockSettingsStore!
    private var handler: SettingsHandler!

    override func setUp() {
        super.setUp()
        store = MockSettingsStore()
        handler = SettingsHandler(store: store)
    }

    func testPathPrefix() {
        XCTAssertEqual(handler.pathPrefix, "/settings")
    }

    func testGetAllSettings() async {
        store.settings = ["theme": "dark", "lang": "en"]

        let response = await handler.handle(method: "GET", uri: "/settings", body: nil)

        XCTAssertEqual(response.statusCode, 200)
        let json = try! JSONSerialization.jsonObject(with: response.body!) as! [String: String]
        XCTAssertEqual(json, ["theme": "dark", "lang": "en"])
    }

    func testGetSingleSetting() async {
        store.settings = ["theme": "dark"]

        let response = await handler.handle(method: "GET", uri: "/settings/theme", body: nil)

        XCTAssertEqual(response.statusCode, 200)
        let value = String(data: response.body!, encoding: .utf8)
        XCTAssertEqual(value, "\"dark\"")
    }

    func testGetMissingSetting() async {
        let response = await handler.handle(method: "GET", uri: "/settings/missing", body: nil)
        XCTAssertEqual(response.statusCode, 404)
    }

    func testPutSingleSetting() async {
        let body = "\"dark\"".data(using: .utf8)!

        let response = await handler.handle(method: "PUT", uri: "/settings/theme", body: body)

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertEqual(store.settings["theme"], "dark")
    }

    func testPutAllSettings() async {
        store.settings = ["old": "value"]
        let body = try! JSONSerialization.data(withJSONObject: ["new": "value"])

        let response = await handler.handle(method: "PUT", uri: "/settings", body: body)

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertEqual(store.settings, ["new": "value"])
    }

    func testDeleteSingleSetting() async {
        store.settings = ["theme": "dark"]

        let response = await handler.handle(method: "DELETE", uri: "/settings/theme", body: nil)

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertNil(store.settings["theme"])
    }

    func testDeleteAllSettings() async {
        store.settings = ["a": "1", "b": "2"]

        let response = await handler.handle(method: "DELETE", uri: "/settings", body: nil)

        XCTAssertEqual(response.statusCode, 204)
        XCTAssertTrue(store.settings.isEmpty)
    }

    func testPutBodyTooLargeReturns413() async {
        let body = Data(repeating: 0x41, count: 65_537)

        let response = await handler.handle(method: "PUT", uri: "/settings/key", body: body)

        XCTAssertEqual(response.statusCode, 413)
    }

    func testUnsupportedMethodReturns405() async {
        let response = await handler.handle(method: "PATCH", uri: "/settings", body: nil)
        XCTAssertEqual(response.statusCode, 405)
    }
}
