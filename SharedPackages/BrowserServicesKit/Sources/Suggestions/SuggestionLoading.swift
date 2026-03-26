//
//  SuggestionLoading.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public protocol SuggestionLoading: AnyObject {

    @MainActor
    func getSuggestions(query: String,
                        usingDataSource dataSource: SuggestionLoadingDataSource,
                        completion: @escaping (SuggestionResult?, Error?) -> Void)

}

/// A closure that processes suggestion inputs and returns a `SuggestionResult`.
/// The `SuggestionProcessing` package provides `Processor.process` which matches this signature.
public typealias SuggestionProcessingHandler = (
    _ query: String,
    _ platform: Platform,
    _ bookmarks: [Bookmark],
    _ history: [HistorySuggestion],
    _ openTabs: [BrowserTab],
    _ internalPages: [InternalPage],
    _ apiResult: APIResult?
) throws -> SuggestionResult

public class SuggestionLoader: SuggestionLoading {

    static let remoteSuggestionsUrl = URL(string: "https://duckduckgo.com/ac/")!
    static let searchParameter = "q"
    static let isNavParameter = "is_nav"

    public enum SuggestionLoaderError: Error {
        case noDataSource
        case parsingFailed
        case failedToProcessData
    }

    private let shouldLoadSuggestionsForUserInput: (String) -> Bool
    private let processSuggestions: SuggestionProcessingHandler

    public init(shouldLoadSuggestionsForUserInput: @escaping (String) -> Bool,
                processSuggestions: @escaping SuggestionProcessingHandler) {
        self.shouldLoadSuggestionsForUserInput = shouldLoadSuggestionsForUserInput
        self.processSuggestions = processSuggestions
    }

    @MainActor
    public func getSuggestions(query: String,
                               usingDataSource dataSource: SuggestionLoadingDataSource,
                               completion: @escaping (SuggestionResult?, Error?) -> Void) {

        if query.isEmpty {
            completion(.empty, nil)
            return
        }

        // 1) Getting all necessary data
        let bookmarks = dataSource.bookmarks(for: self)
        let history = dataSource.history(for: self)
        let internalPages = dataSource.internalPages(for: self)
        let openTabs = dataSource.openTabs(for: self)
        var apiResult: APIResult?
        var apiError: Error?

        let shouldLoadSuggestions = shouldLoadSuggestionsForUserInput(query)

        let group = DispatchGroup()
        if shouldLoadSuggestions {
            group.enter()
            dataSource.suggestionLoading(self,
                                         suggestionDataFromUrl: Self.remoteSuggestionsUrl,
                                         withParameters: [ Self.searchParameter: query,
                                                           Self.isNavParameter: "1", // Enables is_nav in the JSON response
                                                         ]) { data, error in
                defer { group.leave() }
                guard let data = data else {
                    apiError = error
                    return
                }
                guard let result = try? JSONDecoder().decode(APIResult.self, from: data) else {
                    apiError = SuggestionLoaderError.parsingFailed
                    return
                }
                apiResult = result
            }
        } else {
            apiResult = nil
        }

        // 2) Processing it
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self else { return }
            do {
                let result = try self.processSuggestions(
                    query,
                    dataSource.platform,
                    bookmarks,
                    history,
                    openTabs,
                    internalPages,
                    apiResult
                )
                DispatchQueue.main.async {
                    completion(result, apiError)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, SuggestionLoaderError.failedToProcessData)
                }
            }
        }
    }
}

public protocol SuggestionLoadingDataSource: AnyObject {

    var platform: Platform { get }

    func bookmarks(for suggestionLoading: SuggestionLoading) -> [Bookmark]

    @MainActor func history(for suggestionLoading: SuggestionLoading) -> [HistorySuggestion]

    @MainActor func internalPages(for suggestionLoading: SuggestionLoading) -> [InternalPage]

    @MainActor func openTabs(for suggestionLoading: SuggestionLoading) -> [BrowserTab]

    func suggestionLoading(_ suggestionLoading: SuggestionLoading,
                           suggestionDataFromUrl url: URL,
                           withParameters parameters: [String: String],
                           completion: @escaping (Data?, Error?) -> Void)

}
