//
//  TranslationLanguageStore.swift
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

/// Reads/writes the web-page-translation target language, defaulting to the device language.
struct TranslationLanguageStore {

    private let appSettings: AppSettings
    private let deviceLanguageCode: String

    init(appSettings: AppSettings = AppUserDefaults(),
         deviceLanguageCode: String = TranslationLanguageStore.deviceLanguageCode()) {
        self.appSettings = appSettings
        self.deviceLanguageCode = deviceLanguageCode
    }

    /// The device's primary language code, iOS 15-compatible (`Locale.language` is iOS 16+).
    static func deviceLanguageCode() -> String {
        if #available(iOS 16.0, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        } else {
            return Locale.current.languageCode ?? "en"
        }
    }

    var targetLanguageCode: String {
        get { appSettings.webPageTranslationTargetLanguage ?? deviceLanguageCode }
        nonmutating set { appSettings.webPageTranslationTargetLanguage = newValue }
    }
}
