//
//  TranslationSettingsViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo

private final class StubAvailability: LanguageAvailabilityProviding {
    var codes: [String] = []
    var statuses: [String: TranslationLanguageStatus] = [:]   // keyed by "source>target"
    func supportedLanguageCodes() async -> [String] { codes }
    func availability(sourceCode: String, targetCode: String) async -> TranslationLanguageStatus {
        statuses["\(sourceCode)>\(targetCode)"] ?? .downloadable
    }
}

private final class MockTranslationAppSettings2: AppSettingsMock {
    var storedTarget: String?
    override var webPageTranslationTargetLanguage: String? {
        get { storedTarget } set { storedTarget = newValue }
    }
}

@available(iOS 18.0, *)
@MainActor
final class TranslationSettingsViewModelTests: XCTestCase {

    private func makeVM(device: String = "en") -> (TranslationSettingsViewModel, StubAvailability, MockTranslationAppSettings2) {
        let availability = StubAvailability()
        let settings = MockTranslationAppSettings2()
        let store = TranslationLanguageStore(appSettings: settings, deviceLanguageCode: device)
        let vm = TranslationSettingsViewModel(store: store, availability: availability)
        return (vm, availability, settings)
    }

    func testLoadBuildsRowsWithStatusRelativeToTarget_excludingTarget() async {
        let (vm, availability, _) = makeVM(device: "en")
        availability.codes = ["en", "fr", "de"]
        availability.statuses = ["fr>en": .installed, "de>en": .downloadable]
        await vm.load()
        // Target "en" is excluded from the source list; rows sorted by display name.
        XCTAssertEqual(vm.rows.map(\.code), ["fr", "de"].sorted { translationLanguageDisplayName(forCode: $0) < translationLanguageDisplayName(forCode: $1) })
        XCTAssertEqual(vm.rows.first(where: { $0.code == "fr" })?.status, .installed)
        XCTAssertEqual(vm.rows.first(where: { $0.code == "de" })?.status, .downloadable)
    }

    func testDefaultTargetIsDeviceLanguage() async {
        let (vm, availability, _) = makeVM(device: "fr")
        availability.codes = ["en", "fr"]
        await vm.load()
        XCTAssertEqual(vm.targetCode, "fr")
    }

    func testSetTargetPersistsAndRecomputes() async {
        let (vm, availability, settings) = makeVM(device: "en")
        availability.codes = ["en", "fr", "de"]
        availability.statuses = ["en>de": .installed, "fr>de": .downloadable]
        await vm.load()
        await vm.setTarget("de")
        XCTAssertEqual(vm.targetCode, "de")
        XCTAssertEqual(settings.storedTarget, "de")
        // Now sources are en + fr (target de excluded), statuses relative to "de".
        XCTAssertEqual(Set(vm.rows.map(\.code)), ["en", "fr"])
        XCTAssertEqual(vm.rows.first(where: { $0.code == "en" })?.status, .installed)
    }

    func testDownloadMarksRowDownloadingAndArmsConfiguration() async {
        let (vm, availability, _) = makeVM(device: "en")
        availability.codes = ["en", "fr"]
        availability.statuses = ["fr>en": .downloadable]
        await vm.load()
        vm.download("fr")
        XCTAssertTrue(vm.rows.first(where: { $0.code == "fr" })?.isDownloading == true)
        XCTAssertNotNil(vm.downloadConfiguration)
    }

    func testCompleteDownloadSuccessRecomputesRowToInstalled() async {
        let (vm, availability, _) = makeVM(device: "en")
        availability.codes = ["en", "fr"]
        availability.statuses = ["fr>en": .downloadable]
        await vm.load()
        vm.download("fr")
        availability.statuses["fr>en"] = .installed   // simulate model now present
        await vm.completeDownload(code: "fr", succeeded: true)
        let row = vm.rows.first(where: { $0.code == "fr" })
        XCTAssertEqual(row?.status, .installed)
        XCTAssertEqual(row?.isDownloading, false)
        XCTAssertNil(vm.downloadConfiguration)
    }

    func testCompleteDownloadFailureClearsDownloadingKeepsDownloadable() async {
        let (vm, availability, _) = makeVM(device: "en")
        availability.codes = ["en", "fr"]
        availability.statuses = ["fr>en": .downloadable]
        await vm.load()
        vm.download("fr")
        await vm.completeDownload(code: "fr", succeeded: false)
        let row = vm.rows.first(where: { $0.code == "fr" })
        XCTAssertEqual(row?.status, .downloadable)
        XCTAssertEqual(row?.isDownloading, false)
    }

    func testCollapsesRegionVariantsKeepingDistinctScripts() {
        let collapsed = TranslationSettingsViewModel.collapsingRegionVariants(["fr", "fr-CA", "en", "en-GB", "zh-Hans", "zh-Hant"])
        XCTAssertEqual(Set(collapsed), ["fr", "en", "zh-Hans", "zh-Hant"])
        XCTAssertFalse(collapsed.contains("fr-CA"))
        XCTAssertFalse(collapsed.contains("en-GB"))
    }

    func testRowsHideUnavailableLanguages() async {
        let (vm, availability, _) = makeVM(device: "en")
        availability.codes = ["en", "fr", "de"]
        availability.statuses = ["fr>en": .downloadable, "de>en": .unavailable]
        await vm.load()
        let codes = vm.rows.map(\.code)
        XCTAssertTrue(codes.contains("fr"))
        XCTAssertFalse(codes.contains("de"))   // .unavailable hidden
    }
}
