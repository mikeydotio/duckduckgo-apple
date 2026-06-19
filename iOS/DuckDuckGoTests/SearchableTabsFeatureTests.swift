//
//  SearchableTabsFeatureTests.swift
//  DuckDuckGoTests
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

import UIKit
import XCTest
@testable import Core
@testable import DuckDuckGo

final class SearchableTabsFeatureTests: XCTestCase {

    func testWhenIPhoneAndFlagOnThenAvailable() {
        let testee = makeFeature(idiom: .phone, flagOn: true)
        XCTAssertTrue(testee.isAvailable)
    }

    func testWhenIPhoneAndFlagOffThenNotAvailable() {
        let testee = makeFeature(idiom: .phone, flagOn: false)
        XCTAssertFalse(testee.isAvailable)
    }

    func testWhenIPadAndFlagOnThenNotAvailable() {
        let testee = makeFeature(idiom: .pad, flagOn: true)
        XCTAssertFalse(testee.isAvailable)
    }

    func testWhenIPadAndFlagOffThenNotAvailable() {
        let testee = makeFeature(idiom: .pad, flagOn: false)
        XCTAssertFalse(testee.isAvailable)
    }

    private func makeFeature(idiom: UIUserInterfaceIdiom, flagOn: Bool) -> SearchableTabsFeature {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: flagOn ? [.searchableTabs] : [])
        return SearchableTabsFeature(featureFlagger: featureFlagger,
                                     userInterfaceIdiomProvider: MockUserInterfaceIdiomProvider(userInterfaceIdiom: idiom))
    }
}

private struct MockUserInterfaceIdiomProvider: UserInterfaceIdiomProviding {
    let userInterfaceIdiom: UIUserInterfaceIdiom
}
