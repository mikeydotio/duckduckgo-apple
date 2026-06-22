//
//  TranslationLanguageAvailability.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Translation

/// Install state of a source→target pair, decoupled from the iOS 18 framework enum.
enum TranslationLanguageStatus: Equatable {
    case installed       // ready offline
    case downloadable    // supported, needs download
    case unavailable     // pair not supported
}

/// Test seam over Apple's `LanguageAvailability`. Codes are BCP-47 (e.g. "en", "zh-Hans").
protocol LanguageAvailabilityProviding {
    func supportedLanguageCodes() async -> [String]
    func availability(sourceCode: String, targetCode: String) async -> TranslationLanguageStatus
}

@available(iOS 18.0, *)
struct SystemLanguageAvailabilityProvider: LanguageAvailabilityProviding {

    func supportedLanguageCodes() async -> [String] {
        let languages = await LanguageAvailability().supportedLanguages
        return languages.map { $0.minimalIdentifier }
    }

    func availability(sourceCode: String, targetCode: String) async -> TranslationLanguageStatus {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: sourceCode),
                                                         to: Locale.Language(identifier: targetCode))
        switch status {
        case .installed: return .installed
        case .supported: return .downloadable
        case .unsupported: return .unavailable
        @unknown default: return .unavailable
        }
    }
}

/// Localized language name for a BCP-47 code, falling back to the code itself.
func translationLanguageDisplayName(forCode code: String, locale: Locale = .current) -> String {
    locale.localizedString(forIdentifier: code)
        ?? locale.localizedString(forLanguageCode: code)
        ?? code
}
