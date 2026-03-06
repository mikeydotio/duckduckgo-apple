//
//  AutoplayPreferencesTests.swift
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
import WebKit
@testable import DuckDuckGo_Privacy_Browser

final class AutoplayPreferencesPersistorMock: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
    var autoplayExceptionsRawValue: [String: String]
    init(autoplayBlockingModeRawValue: String = AutoplayBlockingMode.blockAudio.rawValue,
         autoplayExceptionsRawValue: [String: String] = [:]) {
        self.autoplayBlockingModeRawValue = autoplayBlockingModeRawValue
        self.autoplayExceptionsRawValue = autoplayExceptionsRawValue
    }
}

final class AutoplayPreferencesTests: XCTestCase {

    // MARK: - Default value

    func testDefaultModeIsBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    func testWhenPersistedValueIsInvalidThenDefaultsToBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: "invalidValue")
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    // MARK: - Persistence round-trip

    func testWhenModeIsSetThenPersistorIsUpdated() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.autoplayBlockingMode = .allowAll

        XCTAssertEqual(persistor.autoplayBlockingModeRawValue, AutoplayBlockingMode.allowAll.rawValue)
    }

    func testAllModesRoundTrip() {
        for mode in AutoplayBlockingMode.allCases {
            let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: mode.rawValue)
            let prefs = AutoplayPreferences(persistor: persistor)
            XCTAssertEqual(prefs.autoplayBlockingMode, mode, "Read round-trip failed for mode: \(mode)")
        }
    }

    // MARK: - WKAudiovisualMediaTypes mapping

    func testAllowAllMapsToEmptyMediaTypes() {
        XCTAssertEqual(AutoplayBlockingMode.allowAll.mediaTypesRequiringUserAction, [])
    }

    func testBlockAudioMapsToAudioOnly() {
        XCTAssertEqual(AutoplayBlockingMode.blockAudio.mediaTypesRequiringUserAction, .audio)
    }

    func testBlockAllMapsToAll() {
        XCTAssertEqual(AutoplayBlockingMode.blockAll.mediaTypesRequiringUserAction, .all)
    }

    // MARK: - objectWillChange

    func testObjectWillChangeFiresOnModeChange() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        let expectation = expectation(description: "objectWillChange fires")
        let cancellable = prefs.objectWillChange.sink { expectation.fulfill() }

        prefs.autoplayBlockingMode = .blockAll
        waitForExpectations(timeout: 0)
        withExtendedLifetime(cancellable) {}
    }
}

final class AutoplayExceptionsTests: XCTestCase {

    // MARK: - effectiveMode(for:) resolution

    func testEffectiveModeReturnsExceptionWhenDomainMatches() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue,
            autoplayExceptionsRawValue: ["youtube.com": "allowAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .allowAll)
    }

    func testEffectiveModeFallsBackToGlobalWhenNoDomainMatch() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAll.rawValue,
            autoplayExceptionsRawValue: ["otherdomain.com": "allowAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .blockAll)
    }

    func testEffectiveModeStripsWWWPrefix() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue,
            autoplayExceptionsRawValue: ["youtube.com": "blockAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .blockAll)
    }

    func testEffectiveModeForNilHostFallsBackToGlobal() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayBlockingModeRawValue: AutoplayBlockingMode.allowAll.rawValue
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        let url = URL(string: "about:blank")!
        XCTAssertEqual(prefs.effectiveMode(for: url), .allowAll)
    }

    // MARK: - exceptions persistence

    func testAddExceptionPersistsToStorage() {
        let persistor = AutoplayPreferencesPersistorMock()
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.exceptions["youtube.com"] = .allowAll

        XCTAssertEqual(persistor.autoplayExceptionsRawValue, ["youtube.com": "allowAll"])
    }

    func testRemoveExceptionPersistsToStorage() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayExceptionsRawValue: ["youtube.com": "allowAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.exceptions.removeValue(forKey: "youtube.com")

        XCTAssertTrue(persistor.autoplayExceptionsRawValue.isEmpty)
    }

    func testExceptionsLoadedFromStorageOnInit() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayExceptionsRawValue: ["youtube.com": "blockAll"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.exceptions["youtube.com"], .blockAll)
    }

    func testInvalidExceptionRawValueIsIgnoredOnLoad() {
        let persistor = AutoplayPreferencesPersistorMock(
            autoplayExceptionsRawValue: ["youtube.com": "bogusValue"]
        )
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertNil(prefs.exceptions["youtube.com"])
    }

    func testExceptionsObjectWillChangeFires() {
        let persistor = AutoplayPreferencesPersistorMock()
        let prefs = AutoplayPreferences(persistor: persistor)

        let exp = expectation(description: "objectWillChange")
        let cancellable = prefs.objectWillChange.sink { exp.fulfill() }

        prefs.exceptions["youtube.com"] = .allowAll
        waitForExpectations(timeout: 0)
        withExtendedLifetime(cancellable) {}
    }
}
