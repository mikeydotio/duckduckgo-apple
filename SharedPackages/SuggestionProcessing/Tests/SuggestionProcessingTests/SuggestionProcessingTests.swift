//
//  ProcessorTests.swift
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
import Suggestions
@testable import SuggestionProcessing

final class ProcessorTests: XCTestCase {

    func testEmptyQueryReturnsEmptyResult() throws {
        let result = try Processor.process(
            query: "",
            platform: .desktop,
            bookmarks: [],
            history: [],
            openTabs: [],
            internalPages: [],
            apiResult: nil
        )
        XCTAssertTrue(result.topHits.isEmpty)
        XCTAssertTrue(result.duckduckgoSuggestions.isEmpty)
        XCTAssertTrue(result.localSuggestions.isEmpty)
    }

    func testPhraseSuggestionsReturnedFromAPI() throws {
        var apiResult = APIResult()
        apiResult.items = [
            APIResult.SuggestionResult(phrase: "duckduckgo", isNav: nil),
            APIResult.SuggestionResult(phrase: "duck recipes", isNav: nil),
        ]

        let result = try Processor.process(
            query: "duck",
            platform: .desktop,
            bookmarks: [],
            history: [],
            openTabs: [],
            internalPages: [],
            apiResult: apiResult
        )

        XCTAssertFalse(result.duckduckgoSuggestions.isEmpty)
        XCTAssertTrue(result.duckduckgoSuggestions.contains(Suggestion.phrase(phrase: "duckduckgo")))
    }

    func testBookmarkAppearsInResults() throws {
        let result = try Processor.process(
            query: "duck",
            platform: .desktop,
            bookmarks: [TestBookmark(url: "https://duckduckgo.com", title: "DuckDuckGo", isFavorite: true)],
            history: [],
            openTabs: [],
            internalPages: [],
            apiResult: nil
        )

        let allResults = result.topHits + result.localSuggestions
        let hasDuckDuckGo = allResults.contains(where: { $0.title == "DuckDuckGo" })
        XCTAssertTrue(hasDuckDuckGo, "DuckDuckGo bookmark should appear in results")
    }

    func testHistoryEntryAppearsInResults() throws {
        let result = try Processor.process(
            query: "duck",
            platform: .desktop,
            bookmarks: [],
            history: [TestHistory(
                identifier: UUID(),
                url: URL(string: "https://duck.com")!,
                title: "DuckMail",
                numberOfVisits: 300,
                lastVisit: Date(),
                failedToLoad: false
            )],
            openTabs: [],
            internalPages: [],
            apiResult: nil
        )

        let allResults = result.topHits + result.localSuggestions
        let hasDuckMail = allResults.contains(where: { $0.title == "DuckMail" })
        XCTAssertTrue(hasDuckMail, "DuckMail history entry should appear in results")
    }
}

// MARK: - Test helpers

private struct TestBookmark: Bookmark {
    var url: String
    var title: String
    var isFavorite: Bool
}

private struct TestHistory: HistorySuggestion {
    var identifier: UUID
    var url: URL
    var title: String?
    var numberOfVisits: Int
    var lastVisit: Date
    var failedToLoad: Bool
}
