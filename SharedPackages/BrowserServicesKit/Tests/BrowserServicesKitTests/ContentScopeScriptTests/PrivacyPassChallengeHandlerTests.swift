//
//  PrivacyPassChallengeHandlerTests.swift
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
@testable import BrowserServicesKit

final class PrivacyPassChallengeHandlerTests: XCTestCase {

    @MainActor
    func testWhenResponseIsNot401ThenIsNotChallenge() {
        let handler = PrivacyPassChallengeHandler(tokenManager: MockPrivacyPassTokenManager())
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                       statusCode: 200,
                                       httpVersion: nil,
                                       headerFields: nil)!
        XCTAssertFalse(handler.isPrivacyPassChallenge(response))
    }

    @MainActor
    func testWhenResponseIs401WithoutPrivateTokenThenIsNotChallenge() {
        let handler = PrivacyPassChallengeHandler(tokenManager: MockPrivacyPassTokenManager())
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                       statusCode: 401,
                                       httpVersion: nil,
                                       headerFields: ["WWW-Authenticate": "Bearer"])!
        XCTAssertFalse(handler.isPrivacyPassChallenge(response))
    }

    @MainActor
    func testWhenResponseIs401WithPrivateTokenThenIsChallenge() {
        let handler = PrivacyPassChallengeHandler(tokenManager: MockPrivacyPassTokenManager())
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!,
                                       statusCode: 401,
                                       httpVersion: nil,
                                       headerFields: ["WWW-Authenticate": "PrivateToken challenge=abc, token-key=def"])!
        XCTAssertTrue(handler.isPrivacyPassChallenge(response))
    }

    @MainActor
    func testWhenAuthorizedRequestIsBuiltThenItContainsRequiredHeaders() {
        let handler = PrivacyPassChallengeHandler(tokenManager: MockPrivacyPassTokenManager())
        let url = URL(string: "https://example.com/protected")!
        let request = handler.authorizedRequest(for: url, authorization: "PrivateToken token=:abc123:", referrer: "https://example.com/")

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "PrivateToken token=:abc123:")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-DuckDuckGo-PrivacyPass-Retry"), "1")
    }

    @MainActor
    func testWhenAuthorizedRequestHasNoReferrerThenReferrerHeaderIsAbsent() {
        let handler = PrivacyPassChallengeHandler(tokenManager: MockPrivacyPassTokenManager())
        let url = URL(string: "https://example.com/protected")!
        let request = handler.authorizedRequest(for: url, authorization: "PrivateToken token=:abc:", referrer: nil)

        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }
}

// MARK: - Mock

private final class MockPrivacyPassTokenManager: PrivacyPassTokenManaging {
    func hasCredential(for issuer: String) -> Bool { false }
    func issueCredential(for issuer: String, tokenKeyBase64url: String) async throws {}
    func spendRaw(for issuer: String) async throws -> Data { Data() }
}
