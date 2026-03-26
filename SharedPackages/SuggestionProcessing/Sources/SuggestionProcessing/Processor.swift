//
//  Processor.swift
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
import Suggestions
import SuggestionsProcessorRust

public enum Processor {

    public enum ProcessorError: Error {
        case inputEncodingFailed
        case resultNil
        case resultNotUTF8
        case resultDecodingFailed(underlying: Error)
    }

    public static func process(
        query: String,
        platform: Platform,
        bookmarks: [Bookmark],
        history: [HistorySuggestion],
        openTabs: [BrowserTab],
        internalPages: [InternalPage],
        apiResult: APIResult?
    ) throws -> SuggestionResult {
        let input = ProcessorInput(
            query: query,
            platform: platform == .mobile ? "mobile" : "desktop",
            bookmarks: bookmarks.map { BookmarkDTO(url: $0.url, title: $0.title, isFavorite: $0.isFavorite) },
            history: history.map {
                HistoryDTO(
                    url: $0.url.absoluteString,
                    title: $0.title,
                    numberOfVisits: $0.numberOfVisits,
                    lastVisit: $0.lastVisit.timeIntervalSince1970,
                    failedToLoad: $0.failedToLoad
                )
            },
            openTabs: openTabs.map { OpenTabDTO(url: $0.url.absoluteString, title: $0.title, tabId: $0.tabId) },
            internalPages: internalPages.map { InternalPageDTO(title: $0.title, url: $0.url.absoluteString) },
            apiResult: apiResult?.items.compactMap { item in
                guard let phrase = item.phrase else { return nil }
                return ApiSuggestionDTO(phrase: phrase, isNav: item.isNav)
            }
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let inputData = try? encoder.encode(input),
              let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw ProcessorError.inputEncodingFailed
        }

        let outputJSON: String = try inputJSON.withCString { inputPtr in
            guard let raw = ddg_sp_process_json(inputPtr) else {
                throw ProcessorError.resultNil
            }
            defer { ddg_sp_free_string(raw) }
            guard let s = String(validatingUTF8: raw) else {
                throw ProcessorError.resultNotUTF8
            }
            return s
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output: ProcessorOutput
        do {
            output = try decoder.decode(ProcessorOutput.self, from: Data(outputJSON.utf8))
        } catch {
            throw ProcessorError.resultDecodingFailed(underlying: error)
        }

        return SuggestionResult(
            topHits: output.topHits.compactMap { $0.toSuggestion() },
            duckduckgoSuggestions: output.ddgSuggestions.compactMap { $0.toSuggestion() },
            localSuggestions: output.localSuggestions.compactMap { $0.toSuggestion() }
        )
    }
}

// MARK: - Encodable DTOs

private struct ProcessorInput: Encodable {
    let query: String
    let platform: String
    let bookmarks: [BookmarkDTO]
    let history: [HistoryDTO]
    let openTabs: [OpenTabDTO]
    let internalPages: [InternalPageDTO]
    let apiResult: [ApiSuggestionDTO]?
}

private struct BookmarkDTO: Encodable {
    let url: String
    let title: String
    let isFavorite: Bool
}

private struct HistoryDTO: Encodable {
    let url: String
    let title: String?
    let numberOfVisits: Int
    let lastVisit: Double
    let failedToLoad: Bool
}

private struct OpenTabDTO: Encodable {
    let url: String
    let title: String
    let tabId: String?
}

private struct InternalPageDTO: Encodable {
    let title: String
    let url: String
}

private struct ApiSuggestionDTO: Encodable {
    let phrase: String
    let isNav: Bool?
}

// MARK: - Decodable output

private struct ProcessorOutput: Decodable {
    let topHits: [SuggestionDTO]
    let ddgSuggestions: [SuggestionDTO]
    let localSuggestions: [SuggestionDTO]
    let canBeAutocompleted: Bool
}

private struct SuggestionDTO: Decodable {
    let `type`: String

    // Common fields
    let url: String?
    let title: String?
    let score: Int?
    let phrase: String?
    let value: String?
    let isFavorite: Bool?
    let tabId: String?

    enum CodingKeys: String, CodingKey {
        case `type`
        case url
        case title
        case score
        case phrase
        case value
        case isFavorite
        case tabId
    }

    func toSuggestion() -> Suggestion? {
        switch `type` {
        case "phrase":
            guard let phrase else { return nil }
            return .phrase(phrase: phrase)
        case "website":
            guard let urlStr = url, let parsedUrl = URL(string: urlStr) else { return nil }
            return .website(url: parsedUrl)
        case "bookmark":
            guard let title, let urlStr = url, let parsedUrl = URL(string: urlStr) else { return nil }
            return .bookmark(title: title, url: parsedUrl, isFavorite: isFavorite ?? false, score: score ?? 0)
        case "history_entry":
            guard let urlStr = url, let parsedUrl = URL(string: urlStr) else { return nil }
            return .historyEntry(title: title, url: parsedUrl, score: score ?? 0)
        case "internal_page":
            guard let title, let urlStr = url, let parsedUrl = URL(string: urlStr) else { return nil }
            return .internalPage(title: title, url: parsedUrl, score: score ?? 0)
        case "open_tab":
            guard let title, let urlStr = url, let parsedUrl = URL(string: urlStr) else { return nil }
            return .openTab(title: title, url: parsedUrl, tabId: tabId, score: score ?? 0)
        case "unknown":
            guard let value else { return nil }
            return .unknown(value: value)
        case "ask_ai_chat":
            guard let value else { return nil }
            return .askAIChat(value: value)
        default:
            return nil
        }
    }
}
