//
//  IntegrationTests.swift
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

final class IntegrationTests: XCTestCase {

    private var server: RealDuckAILocalServer!
    private var baseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let store = InMemorySettingsStore()
        let settingsHandler = SettingsHandler(store: store)
        server = RealDuckAILocalServer(handlers: [settingsHandler])
        try await server.start()
        baseURL = URL(string: "http://127.0.0.1:\(server.port)")!
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        baseURL = nil
        try await super.tearDown()
    }

    func testSettingsRoundTrip() async throws {
        var putRequest = URLRequest(url: baseURL.appendingPathComponent("settings/theme"))
        putRequest.httpMethod = "PUT"
        putRequest.setValue("https://duckduckgo.com", forHTTPHeaderField: "Origin")
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putRequest.httpBody = try JSONEncoder().encode("dark")

        let (_, putResponse) = try await URLSession.shared.data(for: putRequest)
        XCTAssertEqual((putResponse as? HTTPURLResponse)?.statusCode, 204)

        var getRequest = URLRequest(url: baseURL.appendingPathComponent("settings/theme"))
        getRequest.httpMethod = "GET"
        getRequest.setValue("https://duckduckgo.com", forHTTPHeaderField: "Origin")

        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)
        XCTAssertEqual((getResponse as? HTTPURLResponse)?.statusCode, 200)
        let value = try JSONDecoder().decode(String.self, from: getData)
        XCTAssertEqual(value, "dark")
    }

    func testOriginValidationRejects() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("settings"))
        request.httpMethod = "GET"
        request.setValue("https://evil.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
    }

    func testCORSHeaders() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("settings"))
        request.httpMethod = "GET"
        request.setValue("https://duckduckgo.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "https://duckduckgo.com")
    }

    func testOptionsPreflightReturns204() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("settings"))
        request.httpMethod = "OPTIONS"
        request.setValue("https://duckduckgo.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        XCTAssertEqual(httpResponse?.statusCode, 204)
        XCTAssertEqual(httpResponse?.value(forHTTPHeaderField: "Access-Control-Max-Age"), "86400")
    }

    func testUnmatchedRouteReturns404() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("settingsBackup"))
        request.httpMethod = "GET"
        request.setValue("https://duckduckgo.com", forHTTPHeaderField: "Origin")

        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }
}

private final class InMemorySettingsStore: DuckAISettingsStore, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func get(key: String) -> String? { storage[key] }
    func getAll() -> [String: String] { storage }
    func set(key: String, value: String) { storage[key] = value }
    func replaceAll(settings: [String: String]) { storage = settings }
    func delete(key: String) { storage.removeValue(forKey: key) }
    func deleteAll() { storage.removeAll() }
    var isMigrationDone: Bool { false }
    func setMigrationDone() {}
}
