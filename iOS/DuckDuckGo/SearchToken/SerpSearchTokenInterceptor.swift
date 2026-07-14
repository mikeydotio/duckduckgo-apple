//
//  SerpSearchTokenInterceptor.swift
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

import Foundation
import Core
import AIChat

/// Builds the Search Token experiment request mutations for SERP navigations. Pure and
/// WebKit-free so it is unit-testable; `TabViewController` performs the cancel+reload using
/// the request this returns.
enum SerpSearchTokenInterceptor {

    static let dindexParam = "dindexexp"
    static let tokenHeader = "X-DDG-Search-Token"

    /// A DuckDuckGo search-results URL that is not a Duck AI chat query.
    static func isSerpURL(_ url: URL) -> Bool {
        url.isDuckDuckGoSearch && !url.isDuckAIURL
    }
}
