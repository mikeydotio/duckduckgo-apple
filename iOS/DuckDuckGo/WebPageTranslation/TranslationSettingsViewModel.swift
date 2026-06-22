//
//  TranslationSettingsViewModel.swift
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

struct TranslationLanguageRow: Identifiable, Equatable {
    let code: String
    let displayName: String
    var status: TranslationLanguageStatus
    var isDownloading: Bool = false
    var id: String { code }
}

@available(iOS 18.0, *)
@MainActor
final class TranslationSettingsViewModel: ObservableObject {

    @Published private(set) var rows: [TranslationLanguageRow] = []
    @Published private(set) var targetCode: String
    @Published private(set) var allLanguageCodes: [String] = []

    // Set by the view's .translationTask to trigger a download; see Task 4.
    @Published var downloadConfiguration: TranslationSession.Configuration?

    private let store: TranslationLanguageStore
    private let availability: LanguageAvailabilityProviding

    init(store: TranslationLanguageStore = TranslationLanguageStore(),
         availability: LanguageAvailabilityProviding = SystemLanguageAvailabilityProvider()) {
        self.store = store
        self.availability = availability
        self.targetCode = store.targetLanguageCode
    }

    var targetDisplayName: String { translationLanguageDisplayName(forCode: targetCode) }

    func load() async {
        let supported = await availability.supportedLanguageCodes()
        allLanguageCodes = Self.collapsingRegionVariants(supported)
            .sorted { translationLanguageDisplayName(forCode: $0) < translationLanguageDisplayName(forCode: $1) }
        await rebuildRows()
    }

    /// Collapses codes that differ only by region (e.g. "fr" and "fr-CA" → "fr"), preferring the
    /// region-less variant. Distinct scripts are kept (e.g. "zh-Hans" vs "zh-Hant").
    static func collapsingRegionVariants(_ codes: [String]) -> [String] {
        func key(_ code: String) -> String {
            let language = Locale.Language(identifier: code)
            return (language.languageCode?.identifier ?? code) + "|" + (language.script?.identifier ?? "")
        }
        func hasRegion(_ code: String) -> Bool {
            Locale.Language(identifier: code).region != nil
        }
        var bestByKey: [String: String] = [:]
        var keyOrder: [String] = []
        for code in codes {
            let languageKey = key(code)
            if let existing = bestByKey[languageKey] {
                if hasRegion(existing) && !hasRegion(code) { bestByKey[languageKey] = code }
            } else {
                bestByKey[languageKey] = code
                keyOrder.append(languageKey)
            }
        }
        return keyOrder.compactMap { bestByKey[$0] }
    }

    func setTarget(_ code: String) async {
        guard code != targetCode else { return }
        targetCode = code
        store.targetLanguageCode = code
        await rebuildRows()
    }

    private func rebuildRows() async {
        let target = targetCode
        let sources = allLanguageCodes.filter { $0 != target }
        var built: [TranslationLanguageRow] = []
        for code in sources {
            let status = await availability.availability(sourceCode: code, targetCode: target)
            guard status != .unavailable else { continue }   // hide languages that can't translate into the target
            built.append(TranslationLanguageRow(code: code,
                                                displayName: translationLanguageDisplayName(forCode: code),
                                                status: status))
        }
        rows = built
    }

    private var downloadingCode: String?

    /// Begins a download for `code`: marks the row downloading and arms the .translationTask configuration.
    func download(_ code: String) {
        guard let index = rows.firstIndex(where: { $0.code == code }), !rows[index].isDownloading else { return }
        rows[index].isDownloading = true
        downloadingCode = code
        downloadConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: code),
                                                                 target: Locale.Language(identifier: targetCode))
    }

    /// Invoked by the view's .translationTask with a live session: downloads, then recomputes.
    func performDownload(using session: TranslationSession) async {
        guard let code = downloadingCode else { return }
        do {
            try await session.prepareTranslation()
            await completeDownload(code: code, succeeded: true)
        } catch {
            await completeDownload(code: code, succeeded: false)
        }
    }

    /// Clears the transient state; on success recomputes the row's status from availability.
    func completeDownload(code: String, succeeded: Bool) async {
        downloadConfiguration = nil
        downloadingCode = nil
        guard let index = rows.firstIndex(where: { $0.code == code }) else { return }
        rows[index].isDownloading = false
        if succeeded {
            rows[index].status = await availability.availability(sourceCode: code, targetCode: targetCode)
        }
    }
}
