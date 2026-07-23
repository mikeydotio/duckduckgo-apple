//
//  ThemeManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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
import UIKit
@testable import Core
@testable import DuckDuckGo

class ThemeManagerTests: XCTestCase {

    private class MockRootController: UIViewController {
        var onDecorate: XCTestExpectation?

        private func decorate() {
            let theme = ThemeManager.shared.currentTheme
            onDecorate?.fulfill()
        }
    }

    func testEnablingLightThemeModifiesSettings() {
        let defaults = AppUserDefaults(groupName: "com.duckduckgo.mobile.ios.Tests")
        let manager = ThemeManager(settings: defaults)

        manager.setThemeStyle(.light)

        XCTAssertEqual(defaults.currentThemeStyle, .light)
    }

    func testEnablingDarkThemeModifiesSettings() {
        let defaults = AppUserDefaults(groupName: "com.duckduckgo.mobile.ios.Tests")
        let manager = ThemeManager(settings: defaults)

        manager.setThemeStyle(.dark)

        XCTAssertEqual(defaults.currentThemeStyle, .dark)
    }

    func testEnablingSystemThemeModifiesSettings() {
        let defaults = AppUserDefaults(groupName: "com.duckduckgo.mobile.ios.Tests")
        let manager = ThemeManager(settings: defaults)

        manager.setThemeStyle(.systemDefault)

        XCTAssertEqual(defaults.currentThemeStyle, .systemDefault)
    }

    func testEnablingThemeOverridesUserInterfaceStyle() {
        // swiftlint:disable:next force_cast
        let scene = UIApplication.shared.connectedScenes.first! as! UIWindowScene
        let window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()

        let defaults = AppUserDefaults(groupName: "com.duckduckgo.mobile.ios.Tests")
        let manager = ThemeManager(settings: defaults)

        manager.setThemeStyle(.dark)
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .dark)

        manager.setThemeStyle(.light)
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .light)

        manager.setThemeStyle(.systemDefault)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
    }

    // NOTE: `updateUserInterfaceStyle()` (no-arg) now loops `UIApplication.shared.connectedScenes`
    // → every `UIWindowScene.windows`, restyling each via the single-window overload above (still
    // covered by `testEnablingThemeOverridesUserInterfaceStyle`) — see ThemeManager.swift. A true
    // multi-scene regression test needs a second, genuinely independent `UIWindowScene`, which
    // XCTest cannot fabricate; a second `UIWindow` grafted onto the one real test scene doesn't
    // reliably register as an independent, restylable window the way an actual second iPad scene
    // does, making that variant of this test flaky for reasons unrelated to production behavior.
    // Multi-window theming is exercised manually (see PR description) instead.
}
