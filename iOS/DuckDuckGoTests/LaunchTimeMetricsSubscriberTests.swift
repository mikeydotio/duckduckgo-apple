//
//  LaunchTimeMetricsSubscriberTests.swift
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
import Core
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

final class LaunchTimeMetricsSubscriberTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let version = "7.100.0"

    private func makeSubscriber(store: KeyValueStoring,
                                fired: @escaping (Pixel.Event, [String: String]) -> Void) -> LaunchTimeMetricsSubscriber {
        LaunchTimeMetricsSubscriber(store: store,
                                    currentAppVersion: version,
                                    dateProvider: { self.now },
                                    fire: fired)
    }

    private func report(count: Int, endOffset: TimeInterval = -60) -> LaunchMetricsReport {
        LaunchMetricsReport(appVersion: version,
                            includesMultipleAppVersions: false,
                            timeStampEnd: now.addingTimeInterval(endOffset),
                            histograms: [.coldStart: [LaunchHistogramBucket(startMs: 123.4, endMs: 456.6, count: count)]])
    }

    func testFiresOnePixelPerDataPointWithRoundedParams() {
        var fired: [(Pixel.Event, [String: String])] = []
        let subscriber = makeSubscriber(store: MockKeyValueStore()) { fired.append(($0, $1)) }

        subscriber.process(reports: [report(count: 2)])

        XCTAssertEqual(fired.count, 2)
        XCTAssertEqual(fired[0].1[PixelParameters.launchTimeMinMs], "123")
        XCTAssertEqual(fired[0].1[PixelParameters.launchTimeMaxMs], "457")
    }

    func testPersistsMarkerAndSuppressesDuplicateDelivery() {
        let store = MockKeyValueStore()
        var fired: [(Pixel.Event, [String: String])] = []
        let subscriber = makeSubscriber(store: store) { fired.append(($0, $1)) }

        let r = report(count: 3)
        subscriber.process(reports: [r])
        XCTAssertEqual(fired.count, 3)

        // A fresh subscriber sharing the same store must not re-fire the same report.
        fired.removeAll()
        let subscriber2 = makeSubscriber(store: store) { fired.append(($0, $1)) }
        subscriber2.process(reports: [r])
        XCTAssertTrue(fired.isEmpty)
    }
}
