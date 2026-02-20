//
//  EventHubTests.swift
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
@testable import BrowserServicesKit

// MARK: - TelemetryEntry Tests

final class TelemetryEntryTests: XCTestCase {

    // MARK: - Bucketing

    func testBucketCountFirstMatchWins() {
        let buckets = [
            BucketConfig(minInclusive: 0, maxExclusive: 1, name: "0"),
            BucketConfig(minInclusive: 1, maxExclusive: 3, name: "1-2"),
            BucketConfig(minInclusive: 3, maxExclusive: 6, name: "3-5"),
            BucketConfig(minInclusive: 40, maxExclusive: nil, name: "40+")
        ]

        XCTAssertEqual(TelemetryEntry.bucketCount(count: 0, buckets: buckets)?.name, "0")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 1, buckets: buckets)?.name, "1-2")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 2, buckets: buckets)?.name, "1-2")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 3, buckets: buckets)?.name, "3-5")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 5, buckets: buckets)?.name, "3-5")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 40, buckets: buckets)?.name, "40+")
        XCTAssertEqual(TelemetryEntry.bucketCount(count: 100, buckets: buckets)?.name, "40+")
    }

    func testBucketCountNoBucketMatched() {
        let buckets = [
            BucketConfig(minInclusive: 1, maxExclusive: 3, name: "1-2")
        ]
        // 0 doesn't match minInclusive: 1
        // But wait - the design says first matching: count >= minInclusive AND count < maxExclusive
        // 0 >= 1 is false, so no match
        XCTAssertNil(TelemetryEntry.bucketCount(count: 0, buckets: buckets))
    }

    func testBucketCountGapInBuckets() {
        let buckets = [
            BucketConfig(minInclusive: 0, maxExclusive: 1, name: "0"),
            BucketConfig(minInclusive: 10, maxExclusive: nil, name: "10+")
        ]
        // count = 5: 5 >= 0 AND 5 < 1 => false. 5 >= 10 => false. No match.
        XCTAssertNil(TelemetryEntry.bucketCount(count: 5, buckets: buckets))
    }

    // MARK: - Period Calculation

    func testPeriodToSeconds() {
        XCTAssertEqual(TelemetryEntry.periodToSeconds(["days": 1]), 86400)
        XCTAssertEqual(TelemetryEntry.periodToSeconds(["hours": 1]), 3600)
        XCTAssertEqual(TelemetryEntry.periodToSeconds(["minutes": 30]), 1800)
        XCTAssertEqual(TelemetryEntry.periodToSeconds(["seconds": 10]), 10)
        XCTAssertEqual(TelemetryEntry.periodToSeconds(["days": 1, "hours": 2, "minutes": 3, "seconds": 4]),
                        86400 + 7200 + 180 + 4)
    }

    // MARK: - Attribution Period

    func testCalculateAttributionPeriodDaily() {
        // 2026-01-02T00:01:00Z → snap to 2026-01-02T00:00:00Z + 86400 → 2026-01-03T00:00:00Z
        let startTime = Date(timeIntervalSince1970: 1_735_776_060) // 2026-01-02T00:01:00Z
        let periodSeconds = 86400
        let result = TelemetryEntry.calculateAttributionPeriod(startTime: startTime, periodSeconds: periodSeconds)
        // 2026-01-03T00:00:00Z = 1735862400
        XCTAssertEqual(result, 1_735_862_400)
    }

    func testCalculateAttributionPeriodHourly() {
        // 2026-01-02T17:15:00Z → snap to 2026-01-02T17:00:00Z + 3600 → 2026-01-02T18:00:00Z
        let startTime = Date(timeIntervalSince1970: 1_735_838_100) // 2026-01-02T17:15:00Z
        let periodSeconds = 3600
        let result = TelemetryEntry.calculateAttributionPeriod(startTime: startTime, periodSeconds: periodSeconds)
        // 2026-01-02T18:00:00Z = 1735840800
        XCTAssertEqual(result, 1_735_840_800)
    }

    func testCalculateAttributionPeriodOnBoundary() {
        // 2026-01-03T00:00:00Z → already on boundary → 2026-01-03T00:00:00Z + 86400 → 2026-01-04T00:00:00Z
        let startTime = Date(timeIntervalSince1970: 1_735_862_400) // 2026-01-03T00:00:00Z
        let periodSeconds = 86400
        let result = TelemetryEntry.calculateAttributionPeriod(startTime: startTime, periodSeconds: periodSeconds)
        // 2026-01-04T00:00:00Z = 1735948800
        XCTAssertEqual(result, 1_735_948_800)
    }

    // MARK: - Config Parsing

    func testTelemetryEntryParsesConfig() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": [
                "period": ["days": 1]
            ],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        ["minInclusive": 0, "maxExclusive": 1, "name": "0"],
                        ["minInclusive": 1, "maxExclusive": 3, "name": "1-2"],
                        ["minInclusive": 40, "name": "40+"]
                    ]
                ] as [String: Any]
            ]
        ]

        let entry = TelemetryEntry(name: "testPixel", config: config, dateProvider: { Date() })
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "testPixel")
    }

    func testTelemetryEntryReturnsNilForMissingPeriod() {
        let config: [String: Any] = [
            "state": "enabled",
            "parameters": [:]
        ]
        let entry = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })
        XCTAssertNil(entry)
    }

    // MARK: - Event Handling

    func testHandleEventIncrementsCounter() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": ["period": ["days": 1]],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        ["minInclusive": 0, "maxExclusive": 10, "name": "0-9"],
                        ["minInclusive": 10, "name": "10+"]
                    ]
                ] as [String: Any]
            ]
        ]

        let entry = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })!
        entry.start()

        entry.handleEvent(type: "adwall")
        entry.handleEvent(type: "adwall")
        entry.handleEvent(type: "adwall")

        let pixel = entry.buildPixel()
        XCTAssertEqual(pixel["count"], "0-9")
    }

    func testHandleEventIgnoresNonMatchingSource() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": ["period": ["days": 1]],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        ["minInclusive": 0, "maxExclusive": 1, "name": "0"],
                        ["minInclusive": 1, "name": "1+"]
                    ]
                ] as [String: Any]
            ]
        ]

        let entry = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })!
        entry.start()

        entry.handleEvent(type: "something_else")

        let pixel = entry.buildPixel()
        XCTAssertEqual(pixel["count"], "0")
    }

    func testHandleEventStopsCountingAtMaxBucket() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": ["period": ["days": 1]],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        ["minInclusive": 0, "maxExclusive": 3, "name": "0-2"],
                        ["minInclusive": 3, "name": "3+"]
                    ]
                ] as [String: Any]
            ]
        ]

        let entry = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })!
        entry.start()

        // Count to 3 (matches "3+" bucket, no further bucket possible)
        for _ in 0..<5 {
            entry.handleEvent(type: "adwall")
        }

        let pixel = entry.buildPixel()
        XCTAssertEqual(pixel["count"], "3+")

        // Verify counter stopped at 3 (stopCounting kicks in after 3)
        let state = entry.persistedState
        XCTAssertEqual(state.parameters["count"]?.data, 3)
        XCTAssertTrue(state.parameters["count"]?.stopCounting ?? false)
    }

    func testFireSkipsWhenNoParametersHaveData() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": ["period": ["days": 1]],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        // Only buckets starting at 1 — count of 0 won't match
                        ["minInclusive": 1, "name": "1+"]
                    ]
                ] as [String: Any]
            ]
        ]

        let entry = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })!
        entry.start()

        // No events → count = 0 → no bucket matches → empty pixel data
        let pixel = entry.buildPixel()
        XCTAssertTrue(pixel.isEmpty)
    }

    // MARK: - Persistence

    func testPersistedStateRoundtrip() {
        let config: [String: Any] = [
            "state": "enabled",
            "trigger": ["period": ["hours": 1]],
            "parameters": [
                "count": [
                    "template": "counter",
                    "source": "adwall",
                    "buckets": [
                        ["minInclusive": 0, "maxExclusive": 5, "name": "0-4"]
                    ]
                ] as [String: Any]
            ]
        ]

        let original = TelemetryEntry(name: "test", config: config, dateProvider: { Date() })!
        original.start()
        original.handleEvent(type: "adwall")

        let state = original.persistedState
        let restored = TelemetryEntry(persistedState: state, dateProvider: { Date() })

        XCTAssertEqual(restored.name, "test")
        XCTAssertEqual(restored.buildPixel()["count"], "0-4")
    }
}

// MARK: - Mock Pixel Firing

final class MockEventHubPixelFiring: EventHubPixelFiring {
    var firedPixels: [(name: String, parameters: [String: String])] = []

    func fireEventHubPixel(named pixelName: String, parameters: [String: String]) {
        firedPixels.append((name: pixelName, parameters: parameters))
    }
}

// MARK: - EventHub Store Tests

final class EventHubStoreTests: XCTestCase {

    func testSaveAndLoadTelemetryState() {
        let defaults = UserDefaults(suiteName: "test.eventHub.\(UUID().uuidString)")!
        let store = UserDefaultsEventHubStore(defaults: defaults)

        let state = TelemetryPersistedState(
            name: "testPixel",
            periodStart: Date(),
            periodEnd: Date().addingTimeInterval(86400),
            periodSeconds: 86400,
            parameters: [
                "count": ParameterPersistedState(
                    template: "counter",
                    data: 5,
                    source: "adwall",
                    buckets: [BucketConfig(minInclusive: 0, maxExclusive: 10, name: "0-9")],
                    stopCounting: false
                )
            ]
        )

        store.saveTelemetryState(state)
        let loaded = store.loadAllTelemetryStates()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "testPixel")
        XCTAssertEqual(loaded.first?.parameters["count"]?.data, 5)

        defaults.removePersistentDomain(forName: defaults.suiteName)
    }

    func testRemoveTelemetryState() {
        let defaults = UserDefaults(suiteName: "test.eventHub.\(UUID().uuidString)")!
        let store = UserDefaultsEventHubStore(defaults: defaults)

        let state = TelemetryPersistedState(
            name: "toRemove",
            periodStart: Date(),
            periodEnd: Date().addingTimeInterval(3600),
            periodSeconds: 3600,
            parameters: [:]
        )

        store.saveTelemetryState(state)
        XCTAssertEqual(store.loadAllTelemetryStates().count, 1)

        store.removeTelemetryState(named: "toRemove")
        XCTAssertEqual(store.loadAllTelemetryStates().count, 0)

        defaults.removePersistentDomain(forName: defaults.suiteName)
    }
}
