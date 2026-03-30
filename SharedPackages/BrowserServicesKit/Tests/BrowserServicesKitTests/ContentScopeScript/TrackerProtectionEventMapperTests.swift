//
//  TrackerProtectionEventMapperTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common
import ContentBlocking
import TrackerRadarKit

final class TrackerProtectionEventMapperTests: XCTestCase {

    private let tld = TLD()

    private func makeTestTDS() -> TrackerData {
        let tracker = KnownTracker(
            domain: "tracker.com",
            defaultAction: .block,
            owner: KnownTracker.Owner(name: "Tracker Inc", displayName: "Tracker Inc", ownedBy: nil),
            prevalence: 0.1,
            subdomains: nil,
            categories: ["Analytics"],
            rules: nil)

        let entity = Entity(displayName: "Tracker Inc", domains: ["tracker.com"], prevalence: 0.1)

        return TrackerData(
            trackers: ["tracker.com": tracker],
            entities: ["Tracker Inc": entity],
            domains: ["tracker.com": "Tracker Inc"],
            cnames: nil)
    }

    private func makeMapper() -> TrackerProtectionEventMapper {
        TrackerProtectionEventMapper(tld: tld,
                                     mainTrackerData: makeTestTDS(),
                                     unprotectedSites: [],
                                     tempList: [],
                                     contentBlockingEnabled: true)
    }

    // MARK: - ResourceObservation Classification

    func testWhenTrackerUrlIsObservedThenClassifyReturnsDetectedRequest() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.url, "https://tracker.com/pixel.js")
    }

    func testWhenNonTrackerUrlIsObservedThenClassifyReturnsNil() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://not-a-tracker.com/script.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNil(result)
    }

    func testWhenFirstPartyTrackerIsObservedThenStateIsOwnedByFirstParty() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://tracker.com")

        let result = mapper.classifyResource(observation)
        XCTAssertNotNil(result)
        if case .allowed(reason: .ownedByFirstParty) = result?.state {
        } else {
            XCTFail("Expected first-party tracker to be allowed with ownedByFirstParty reason")
        }
    }

    // MARK: - SurrogateInjection Classification

    func testWhenSurrogateInjectionIsReceivedThenClassifyReturnsDetectedRequest() {
        let mapper = makeMapper()
        let surrogate = TrackerProtectionSubfeature.SurrogateInjection(
            url: "https://tracker.com/analytics.js",
            pageUrl: "https://example.com",
            surrogateName: "analytics.js")

        let result = mapper.classifySurrogate(surrogate)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.url, "https://tracker.com/analytics.js")
    }

    func testWhenSurrogateHostIsExtractedThenItMatchesUrl() {
        let mapper = makeMapper()
        let surrogate = TrackerProtectionSubfeature.SurrogateInjection(
            url: "https://tracker.com/analytics.js",
            pageUrl: "https://example.com",
            surrogateName: "analytics.js")

        XCTAssertEqual(mapper.surrogateHost(from: surrogate), "tracker.com")
    }

    // MARK: - Same-Site Detection

    func testWhenObservationIsSameSiteThenIsSameSiteReturnsTrue() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://cdn.example.com/script.js",
            resourceType: "script",
            potentiallyBlocked: false,
            pageUrl: "https://example.com")

        XCTAssertTrue(mapper.isSameSiteObservation(observation))
    }

    func testWhenObservationIsCrossSiteThenIsSameSiteReturnsFalse() {
        let mapper = makeMapper()
        let observation = TrackerProtectionSubfeature.ResourceObservation(
            url: "https://tracker.com/pixel.js",
            resourceType: "script",
            potentiallyBlocked: true,
            pageUrl: "https://example.com")

        XCTAssertFalse(mapper.isSameSiteObservation(observation))
    }
}
