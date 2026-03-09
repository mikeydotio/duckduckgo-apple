//
//  StartupPreferences.swift
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

import AppKit
import BrowserServicesKit
import Combine
import Foundation
import FeatureFlags
import Persistence

enum HomePageMode: String, CaseIterable {
    case newTabPage
    case blankPage
    case specificPage
}

enum StartupWindowType: String, CaseIterable {
    case window = "window"
    case fireWindow = "fire-window"

    var displayName: String {
        switch self {
        case .window:
            return UserText.window
        case .fireWindow:
            return UserText.fireWindow
        }
    }

    /// Returns the corresponding BurnerMode for this window type
    /// - Returns: The appropriate BurnerMode
    func toBurnerMode() -> BurnerMode {
        switch self {
        case .window:
            return .regular
        case .fireWindow:
            return BurnerMode(isBurner: true)
        }
    }
}

protocol StartupPreferencesPersistor {
    var restorePreviousSession: Bool { get set }
    var homePageMode: HomePageMode { get set }
    var customHomePageURL: String { get set }
    var startupWindowType: StartupWindowType { get set }
}

struct StartupPreferencesUserDefaultsPersistor: StartupPreferencesPersistor {
    enum Key: String {
        case startupWindowType = "startup-window-type"
        case homePageMode = "home-page-mode"
    }

    @UserDefaultsWrapper(key: .restorePreviousSession, defaultValue: false)
    var restorePreviousSession: Bool

    @UserDefaultsWrapper(key: .launchToCustomHomePage, defaultValue: false)
    private var legacyLaunchToCustomHomePage: Bool

    @UserDefaultsWrapper(key: .customHomePageURL, defaultValue: URL.duckDuckGo.absoluteString)
    var customHomePageURL: String

    var homePageMode: HomePageMode {
        get {
            do {
                if let value = try keyValueStore.object(forKey: Key.homePageMode.rawValue) as? String,
                   let mode = HomePageMode(rawValue: value) {
                    return mode
                }
            } catch {}
            // Migrate from legacy boolean
            return legacyLaunchToCustomHomePage ? .specificPage : .newTabPage
        }
        set { try? keyValueStore.set(newValue.rawValue, forKey: Key.homePageMode.rawValue) }
    }

    var startupWindowType: StartupWindowType {
        get {
            do {
                let value = try keyValueStore.object(forKey: Key.startupWindowType.rawValue) as? String ?? StartupWindowType.window.rawValue
                return StartupWindowType(rawValue: value) ?? .window
            } catch {
                return .window
            }
        }
        set { try? keyValueStore.set(newValue.rawValue, forKey: Key.startupWindowType.rawValue) }
    }

    /**
     * Initializes Startup Preferences persistor.
     *
     * - Parameters:
     *   - keyValueStore: An instance of `ThrowingKeyValueStoring` that is supposed to hold all newly added preferences.
     *   - legacyKeyValueStore: An instance of `KeyValueStoring` (wrapper for `UserDefaults`) that can be used for migrating existing
     *                          preferences to the new store.
     *
     *  `keyValueStore` is an opt-in mechanism, in that all pre-existing properties of the persistor (especially those using `@UserDefaultsWrapper`)
     *  continue using `legacyKeyValueStore` (a.k.a. `UserDefaults`) and only new properties should use `keyValueStore` by default
     *  (see `isProtectionsReportVisible`).
     */
    init(keyValueStore: ThrowingKeyValueStoring, legacyKeyValueStore: KeyValueStoring = UserDefaultsWrapper<Any>.sharedDefaults) {
        self.keyValueStore = keyValueStore
        self.legacyKeyValueStore = legacyKeyValueStore
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let legacyKeyValueStore: KeyValueStoring

}

final class StartupPreferences: ObservableObject {

    private let pinningManager: PinningManager
    private var appearancePreferences: AppearancePreferences
    private var persistor: StartupPreferencesPersistor
    private var pinnedViewsNotificationCancellable: AnyCancellable?

    init(pinningManager: PinningManager,
         persistor: StartupPreferencesPersistor,
         appearancePreferences: AppearancePreferences) {
        self.pinningManager = pinningManager
        self.appearancePreferences = appearancePreferences
        self.persistor = persistor
        restorePreviousSession = persistor.restorePreviousSession
        homePageMode = persistor.homePageMode
        customHomePageURL = persistor.customHomePageURL
        startupWindowType = persistor.startupWindowType
        updateHomeButtonState()
        listenToPinningManagerNotifications()
    }

    @Published var restorePreviousSession: Bool {
        didSet {
            persistor.restorePreviousSession = restorePreviousSession
        }
    }

    @Published var homePageMode: HomePageMode {
        didSet {
            persistor.homePageMode = homePageMode
        }
    }

    @Published var customHomePageURL: String {
        didSet {
            guard let urlWithScheme = urlWithScheme(customHomePageURL) else {
                return
            }
            if customHomePageURL != urlWithScheme {
                customHomePageURL = urlWithScheme
            }
            persistor.customHomePageURL = customHomePageURL
        }
    }

    @Published var startupWindowType: StartupWindowType {
        didSet {
            persistor.startupWindowType = startupWindowType
        }
    }

    @Published var homeButtonPosition: HomeButtonPosition = .hidden

    var formattedCustomHomePageURL: String {
        let trimmedURL = customHomePageURL.trimmingWhitespace()
        guard let url = URL(trimmedAddressBarString: trimmedURL) else {
            return URL.duckDuckGo.absoluteString
        }
        return url.absoluteString
    }

    var friendlyURL: String {
        var friendlyURL = customHomePageURL
        if friendlyURL.count > 30 {
            let index = friendlyURL.index(friendlyURL.startIndex, offsetBy: 27)
            friendlyURL = String(friendlyURL[..<index]) + "..."
        }
        return friendlyURL
    }

    /// Determines the appropriate BurnerMode for new windows based on startup preferences and feature flags
    /// - Returns: The appropriate BurnerMode for the startup window
    func startupBurnerMode() -> BurnerMode {
        return startupWindowType.toBurnerMode()
    }

    func homePageTabContent(source: Tab.TabContent.URLSource = .ui) -> Tab.TabContent {
        switch homePageMode {
        case .newTabPage:
            return .newtab
        case .blankPage:
            return .url(.blankPage, source: source)
        case .specificPage:
            if let customURL = URL(string: formattedCustomHomePageURL),
               customURL != URL.Invalid.aboutHome {
                return Tab.TabContent.contentFromURL(customURL, source: source)
            }
            return .newtab
        }
    }

    func isValidURL(_ text: String) -> Bool {
        guard let url = text.url else { return false }
        return !text.isEmpty && url.isValid
    }

    func updateHomeButton() {
        appearancePreferences.homeButtonPosition = homeButtonPosition
        if homeButtonPosition != .hidden {
            pinningManager.unpin(.homeButton)
            pinningManager.pin(.homeButton)
        } else {
            pinningManager.unpin(.homeButton)
        }
    }

    private func updateHomeButtonState() {
        homeButtonPosition = pinningManager.isPinned(.homeButton) ? appearancePreferences.homeButtonPosition : .hidden
    }

    private func listenToPinningManagerNotifications() {
        pinnedViewsNotificationCancellable = NotificationCenter.default.publisher(for: .PinnedViewsChanged).sink { [weak self] _ in
            guard let self = self else {
                return
            }
            self.updateHomeButtonState()
        }
    }

    private func urlWithScheme(_ urlString: String) -> String? {
        guard var urlWithScheme = urlString.url else {
            return nil
        }
        // Force 'https' if 'http' not explicitly set by user
        if urlWithScheme.isHttp && !urlString.hasPrefix(URL.NavigationalScheme.http.separated()) {
            urlWithScheme = urlWithScheme.toHttps() ?? urlWithScheme
        }
        return urlWithScheme.toString(decodePunycode: true, dropScheme: false, dropTrailingSlash: true)
    }

}
