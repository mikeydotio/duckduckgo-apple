//
//  JSFileCacheTests.swift
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

import Foundation
import XCTest
@testable import UserScript

class JSFileCacheTests: XCTestCase {

    // MARK: - applyReplacements

    func testSingleTokenReplacement() {
        let template = "var config = $CONFIG$;"
        let result = JSFileCache.applyReplacements(template, ["$CONFIG$": "{\"enabled\":true}"])
        XCTAssertEqual(result, "var config = {\"enabled\":true};")
    }

    func testMultipleReplacements() {
        let template = "var a = $A$; var b = $B$;"
        let result = JSFileCache.applyReplacements(template, ["$A$": "1", "$B$": "2"])
        XCTAssertEqual(result, "var a = 1; var b = 2;")
    }

    func testRepeatedTokenReplacedAtAllOccurrences() {
        let template = "$TOKEN$ and $TOKEN$"
        let result = JSFileCache.applyReplacements(template, ["$TOKEN$": "value"])
        XCTAssertEqual(result, "value and value")
    }

    func testEmptyReplacementsReturnsTemplateUnchanged() {
        let template = "var x = $KEEP$;"
        let result = JSFileCache.applyReplacements(template, [:])
        XCTAssertEqual(result, template)
    }

    func testUnmatchedDollarSignPassesThrough() {
        let template = "price is $5 and $TOKEN$ is replaced"
        let result = JSFileCache.applyReplacements(template, ["$TOKEN$": "value"])
        XCTAssertEqual(result, "price is $5 and value is replaced")
    }

    func testAdjacentTokensReplacedCorrectly() {
        let template = "$A$$B$"
        let result = JSFileCache.applyReplacements(template, ["$A$": "first", "$B$": "second"])
        XCTAssertEqual(result, "firstsecond")
    }

    func testNoTokensInTemplate() {
        let template = "no tokens here"
        let result = JSFileCache.applyReplacements(template, ["$TOKEN$": "value"])
        XCTAssertEqual(result, "no tokens here")
    }

    func testUnicodeInTemplateAndReplacements() {
        let template = "var label = $LABEL$; var emoji = \u{1F600}; var config = $CONFIG$;"
        let result = JSFileCache.applyReplacements(template, [
            "$LABEL$": "\"Datenschutz-Einstellungen\"",
            "$CONFIG$": "{\"emoji\":\"\u{1F525}\",\"cjk\":\"\u{4E16}\u{754C}\"}"
        ])
        XCTAssertEqual(result, "var label = \"Datenschutz-Einstellungen\"; var emoji = \u{1F600}; var config = {\"emoji\":\"\u{1F525}\",\"cjk\":\"\u{4E16}\u{754C}\"};")
    }

    // MARK: - content(forFile:in:)

    func testContentReturnsFileFromBundle() throws {
        let content = try JSFileCache.content(forFile: "testUserScript", in: .module)
        XCTAssertTrue(content.contains("var val"))
    }

    func testContentThrowsForMissingFile() {
        XCTAssertThrowsError(try JSFileCache.content(forFile: "nonExistentFile", in: .module)) { error in
            guard case let UserScriptError.failedToLoadJS(jsFile, _) = error else {
                return XCTFail("Expected failedToLoadJS error but got: \(error)")
            }
            XCTAssertEqual(jsFile, "nonExistentFile")
        }
    }

    func testContentReturnsSameResultOnSecondCall() throws {
        let first = try JSFileCache.content(forFile: "testUserScript", in: .module)
        let second = try JSFileCache.content(forFile: "testUserScript", in: .module)
        XCTAssertEqual(first, second)
    }
}
