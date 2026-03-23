//
//  OriginValidatorTests.swift
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

final class OriginValidatorTests: XCTestCase {

    func testAllowsDuckDuckGo() {
        XCTAssertTrue(OriginValidator.isAllowed(origin: "https://duckduckgo.com"))
    }

    func testAllowsDuckAi() {
        XCTAssertTrue(OriginValidator.isAllowed(origin: "https://duck.ai"))
    }

    func testRejectsUnknownOrigin() {
        XCTAssertFalse(OriginValidator.isAllowed(origin: "https://evil.com"))
    }

    func testRejectsNilOrigin() {
        XCTAssertFalse(OriginValidator.isAllowed(origin: nil))
    }

    func testRejectsEmptyOrigin() {
        XCTAssertFalse(OriginValidator.isAllowed(origin: ""))
    }

    func testRejectsHTTPOrigin() {
        XCTAssertFalse(OriginValidator.isAllowed(origin: "http://duckduckgo.com"))
    }
}
