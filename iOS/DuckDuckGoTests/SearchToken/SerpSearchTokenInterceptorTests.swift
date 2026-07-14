//
//  SerpSearchTokenInterceptorTests.swift
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
import Common
@testable import DuckDuckGo

final class SerpSearchTokenInterceptorTests: XCTestCase {

    // MARK: isSerpURL

    func testIsSerpURL_trueForSearchResults() {
        let url = URL(string: "https://duckduckgo.com/?q=privacy")!
        XCTAssertTrue(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForNonSearchDuckDuckGo() {
        let url = URL(string: "https://duckduckgo.com/about")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForDuckAIChatQuery() {
        let url = URL(string: "https://duckduckgo.com/?q=hello&ia=chat")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }

    func testIsSerpURL_falseForNonDuckDuckGo() {
        let url = URL(string: "https://example.com/?q=privacy")!
        XCTAssertFalse(SerpSearchTokenInterceptor.isSerpURL(url))
    }
}
