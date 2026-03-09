//
//  StartupPreferencesTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
@testable import DuckDuckGo_Privacy_Browser

final class StartupPreferencesPersistorMock: StartupPreferencesPersistor {
    var homePageMode: HomePageMode
    var customHomePageURL: String
    var restorePreviousSession: Bool
    var startupWindowType: StartupWindowType

    init(homePageMode: HomePageMode = .newTabPage, customHomePageURL: String = "", restorePreviousSession: Bool = false, startupWindowType: StartupWindowType = .window) {
        self.customHomePageURL = customHomePageURL
        self.homePageMode = homePageMode
        self.restorePreviousSession = restorePreviousSession
        self.startupWindowType = startupWindowType
    }
}

class StartupPreferencesTests: XCTestCase {

    @MainActor
    func testWhenInitializedThenItLoadsPersistedValues() throws {
        var model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .newTabPage, customHomePageURL: "duckduckgo.com", restorePreviousSession: false), appearancePreferences: .mock)
        XCTAssertEqual(model.homePageMode, .newTabPage)
        XCTAssertEqual(model.customHomePageURL, "duckduckgo.com")
        XCTAssertEqual(model.restorePreviousSession, false)
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "http://duckduckgo.com", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.homePageMode, .specificPage)
        XCTAssertEqual(model.customHomePageURL, "http://duckduckgo.com")
        XCTAssertEqual(model.restorePreviousSession, true)
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "https://duckduckgo.com", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.customHomePageURL, "https://duckduckgo.com")
        XCTAssertEqual(model.startupWindowType, .window) // Default value

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "https://mail.google.com/mail/u/1/#spam/FMfcgzGtxKRZFPXfxKMWSKVgwJlswxnH", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.friendlyURL, "https://mail.google.com/mai...")

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "https://www.rnids.rs/национални-домени/регистрација-националних-домена", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.friendlyURL, "https://www.rnids.rs/национ...")

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "www.rnids.rs/национални-домени/регистрација-националних-домена", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.friendlyURL, "www.rnids.rs/национални-дом...")

        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "https://💩.la", restorePreviousSession: true), appearancePreferences: .mock)
        XCTAssertEqual(model.friendlyURL, "https://💩.la")

    }

    @MainActor
    func testIsValidURL() {
        let prefs = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(), appearancePreferences: .mock)
        XCTAssertFalse(prefs.isValidURL("invalid url"))
        XCTAssertFalse(prefs.isValidURL("invalidUrl"))
        XCTAssertFalse(prefs.isValidURL(""))
        XCTAssertTrue(prefs.isValidURL("test.com"))
        XCTAssertTrue(prefs.isValidURL("http://test.com"))
        XCTAssertTrue(prefs.isValidURL("https://test.com"))
    }

    // MARK: - HomePageMode Tests

    func testHomePageModeEnum() {
        XCTAssertEqual(HomePageMode.newTabPage.rawValue, "newTabPage")
        XCTAssertEqual(HomePageMode.blankPage.rawValue, "blankPage")
        XCTAssertEqual(HomePageMode.specificPage.rawValue, "specificPage")

        let allCases = HomePageMode.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.newTabPage))
        XCTAssertTrue(allCases.contains(.blankPage))
        XCTAssertTrue(allCases.contains(.specificPage))
    }

    func testHomePageModeInitialization() {
        XCTAssertEqual(HomePageMode(rawValue: "newTabPage"), .newTabPage)
        XCTAssertEqual(HomePageMode(rawValue: "blankPage"), .blankPage)
        XCTAssertEqual(HomePageMode(rawValue: "specificPage"), .specificPage)
        XCTAssertNil(HomePageMode(rawValue: "invalid"))
    }

    @MainActor
    func testWhenHomePageModeIsUpdatedThenPersistedValueIsUpdated() {
        let persistor = StartupPreferencesPersistorMock()
        let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)

        model.homePageMode = .blankPage
        XCTAssertEqual(persistor.homePageMode, .blankPage)

        model.homePageMode = .specificPage
        XCTAssertEqual(persistor.homePageMode, .specificPage)

        model.homePageMode = .newTabPage
        XCTAssertEqual(persistor.homePageMode, .newTabPage)
    }

    @MainActor
    func testHomePageTabContentReturnsCorrectContentForEachMode() {
        // New Tab Page mode
        var model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .newTabPage), appearancePreferences: .mock)
        XCTAssertEqual(model.homePageTabContent(), .newtab)

        // Blank Page mode
        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .blankPage), appearancePreferences: .mock)
        XCTAssertEqual(model.homePageTabContent(), .url(.blankPage, source: .ui))

        // Specific Page mode
        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .specificPage, customHomePageURL: "https://example.com"), appearancePreferences: .mock)
        let content = model.homePageTabContent()
        if case .url(let url, _, _) = content {
            XCTAssertEqual(url.absoluteString, "https://example.com")
        } else {
            XCTFail("Expected .url content for specificPage mode")
        }
    }

    @MainActor
    func testHomePageTabContentRespectsSourceParameter() {
        let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(homePageMode: .blankPage), appearancePreferences: .mock)

        let uiContent = model.homePageTabContent(source: .ui)
        XCTAssertEqual(uiContent, .url(.blankPage, source: .ui))

        let historyContent = model.homePageTabContent(source: .historyEntry)
        XCTAssertEqual(historyContent, .url(.blankPage, source: .historyEntry))
    }

    // MARK: - StartupWindowType Tests

    func testStartupWindowTypeEnum() {
        // Test enum cases
        XCTAssertEqual(StartupWindowType.window.rawValue, "window")
        XCTAssertEqual(StartupWindowType.fireWindow.rawValue, "fire-window")

        // Test case iterable
        let allCases = StartupWindowType.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.window))
        XCTAssertTrue(allCases.contains(.fireWindow))

        // Test display names
        XCTAssertEqual(StartupWindowType.window.displayName, UserText.window)
        XCTAssertEqual(StartupWindowType.fireWindow.displayName, UserText.fireWindow)
    }

    func testStartupWindowTypeInitialization() {
        // Test initialization from raw value
        XCTAssertEqual(StartupWindowType(rawValue: "window"), .window)
        XCTAssertEqual(StartupWindowType(rawValue: "fire-window"), .fireWindow)
        XCTAssertNil(StartupWindowType(rawValue: "invalid"))
    }

    // MARK: - StartupWindowType Persistence Tests

    @MainActor
    func testWhenInitializedThenItLoadsStartupWindowType() {
        // Test default value
        var model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com"
        ), appearancePreferences: .mock)
        XCTAssertEqual(model.startupWindowType, .window)

        // Test fire window value
        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        ), appearancePreferences: .mock)
        XCTAssertEqual(model.startupWindowType, .fireWindow)

        // Test window value explicitly
        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .window
        ), appearancePreferences: .mock)
        XCTAssertEqual(model.startupWindowType, .window)
    }

    @MainActor
    func testWhenStartupWindowTypeIsUpdatedThenPersistedValueIsUpdated() {
        class TestPersistor: StartupPreferencesPersistor {
            var homePageMode: HomePageMode
            var customHomePageURL: String
            var restorePreviousSession: Bool
            var startupWindowType: StartupWindowType {
                didSet {
                    startupWindowTypeSetCalls.append(startupWindowType)
                }
            }
            var startupWindowTypeSetCalls: [StartupWindowType] = []

            init(homePageMode: HomePageMode = .newTabPage, customHomePageURL: String, restorePreviousSession: Bool = false, startupWindowType: StartupWindowType = .window) {
                self.homePageMode = homePageMode
                self.customHomePageURL = customHomePageURL
                self.restorePreviousSession = restorePreviousSession
                self.startupWindowType = startupWindowType
            }
        }

        let persistor = TestPersistor(
            customHomePageURL: "duckduckgo.com"
        )
        let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)

        // Initial value should not trigger a set call during initialization
        XCTAssertTrue(persistor.startupWindowTypeSetCalls.isEmpty)

        // Test changing to fire window
        model.startupWindowType = .fireWindow
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.fireWindow])
        XCTAssertEqual(persistor.startupWindowType, .fireWindow)

        // Test changing back to regular window
        model.startupWindowType = .window
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.fireWindow, .window])
        XCTAssertEqual(persistor.startupWindowType, .window)

        // Test setting same value calls persistor (this is expected behavior)
        persistor.startupWindowTypeSetCalls.removeAll()
        model.startupWindowType = .window
        XCTAssertEqual(persistor.startupWindowTypeSetCalls, [.window])
    }

    // MARK: - Enhanced Initialization Tests

    @MainActor
    func testWhenInitializedWithAllPropertiesThenItLoadsAllPersistedValues() {
        let persistor = StartupPreferencesPersistorMock(
            homePageMode: .specificPage,
            customHomePageURL: "https://example.com",
            restorePreviousSession: true,
            startupWindowType: .fireWindow
        )

        let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)

        XCTAssertEqual(model.homePageMode, .specificPage)
        XCTAssertEqual(model.customHomePageURL, "https://example.com")
        XCTAssertEqual(model.restorePreviousSession, true)
        XCTAssertEqual(model.startupWindowType, .fireWindow)
    }

    @MainActor
    func testWhenInitializedWithMixedPropertiesThenItLoadsCorrectValues() {
        // Test various combinations to ensure property independence
        let combinations: [(HomePageMode, String, Bool, StartupWindowType)] = [
            (.newTabPage, "duckduckgo.com", false, .window),
            (.specificPage, "https://example.com", false, .fireWindow),
            (.blankPage, "https://test.com", true, .fireWindow),
            (.specificPage, "duckduckgo.com", true, .window)
        ]

        for (homePageMode, url, restoreSession, windowType) in combinations {
            let persistor = StartupPreferencesPersistorMock(
                homePageMode: homePageMode,
                customHomePageURL: url,
                restorePreviousSession: restoreSession,
                startupWindowType: windowType
            )

            let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)

            XCTAssertEqual(model.homePageMode, homePageMode)
            XCTAssertEqual(model.customHomePageURL, url)
            XCTAssertEqual(model.restorePreviousSession, restoreSession)
            XCTAssertEqual(model.startupWindowType, windowType)
        }
    }

    // MARK: - Startup Burner Mode Tests

    @MainActor
    func testStartupBurnerMode() {
        // Test with regular window type - should return regular mode
        var persistor = StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .window
        )
        var model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)
        var burnerMode = model.startupBurnerMode()
        XCTAssertEqual(burnerMode, .regular)

        // Test with fire window type - should return burner mode when feature flag is on
        persistor = StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        )
        model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)
        burnerMode = model.startupBurnerMode()
        XCTAssertTrue(burnerMode.isBurner)
    }

    @MainActor
    func testStartupBurnerModeEdgeCases() {
        let featureFlagger = MockFeatureFlagger()

        let persistor = StartupPreferencesPersistorMock(
            customHomePageURL: "duckduckgo.com",
            startupWindowType: .fireWindow
        )
        let model = StartupPreferences(pinningManager: MockPinningManager(), persistor: persistor, appearancePreferences: .mock)

        // Test multiple calls return consistent results
        let burnerMode1 = model.startupBurnerMode()
        let burnerMode2 = model.startupBurnerMode()
        XCTAssertEqual(burnerMode1.isBurner, burnerMode2.isBurner)

        // Test state change
        model.startupWindowType = .window
        let regularMode = model.startupBurnerMode()
        XCTAssertEqual(regularMode, .regular)
    }

}

fileprivate extension StartupPreferences {
    @MainActor
    convenience init(persistor: StartupPreferencesPersistor = StartupPreferencesPersistorMock()) {
        self.init(
            pinningManager: MockPinningManager(),
            persistor: persistor,
            appearancePreferences: AppearancePreferences(
                persistor: AppearancePreferencesPersistorMock(),
                privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                featureFlagger: MockFeatureFlagger(),
                aiChatMenuConfig: MockAIChatConfig()
            )
        )
    }
}
