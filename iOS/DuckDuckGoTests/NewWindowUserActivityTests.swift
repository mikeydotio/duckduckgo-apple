//
//  NewWindowUserActivityTests.swift
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

import XCTest
@testable import DuckDuckGo

class NewWindowUserActivityTests: XCTestCase {

    func testMakeWithURL_roundTripsTheURL() {
        let url = URL(string: "https://duckduckgo.com")!
        let activity = NewWindowUserActivity.make(url: url)

        XCTAssertEqual(activity.activityType, NewWindowUserActivity.activityType)
        XCTAssertEqual(NewWindowUserActivity.url(from: activity), url)
    }

    func testMakeWithNilURL_roundTripsToNil() {
        let activity = NewWindowUserActivity.make(url: nil)

        XCTAssertEqual(activity.activityType, NewWindowUserActivity.activityType)
        XCTAssertNil(NewWindowUserActivity.url(from: activity))
    }

    func testUrlFrom_ignoresUnrelatedActivityTypes() {
        let unrelated = NSUserActivity(activityType: "com.example.unrelated")
        unrelated.userInfo = ["url": URL(string: "https://duckduckgo.com")!]

        XCTAssertNil(NewWindowUserActivity.url(from: unrelated))
    }

}
