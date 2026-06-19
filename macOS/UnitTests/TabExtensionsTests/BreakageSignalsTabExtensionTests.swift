//
//  BreakageSignalsTabExtensionTests.swift
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

import Navigation
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class BreakageSignalsTabExtensionTests: XCTestCase {

    // _WKRenderingProgressEvents bits (mirrors WebKit).
    private let firstLayout: UInt = 1 << 0                 // not a "drew content" milestone
    private let firstVisuallyNonEmptyLayout: UInt = 1 << 1 // drew content
    private let firstMeaningfulPaint: UInt = 1 << 8        // drew content

    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTiming(navigationStart: Date? = nil,
                            firstVisualLayout: Date? = nil,
                            firstMeaningfulPaint: Date? = nil,
                            documentFinishedLoading: Date? = nil,
                            allSubresourcesFinishedLoading: Date? = nil) -> WKPageLoadTiming {
        let dict = NSMutableDictionary()
        if let navigationStart { dict["navigationStart"] = navigationStart }
        if let firstVisualLayout { dict["firstVisualLayout"] = firstVisualLayout }
        if let firstMeaningfulPaint { dict["firstMeaningfulPaint"] = firstMeaningfulPaint }
        if let documentFinishedLoading { dict["documentFinishedLoading"] = documentFinishedLoading }
        if let allSubresourcesFinishedLoading { dict["allSubresourcesFinishedLoading"] = allSubresourcesFinishedLoading }
        return WKPageLoadTiming(dict)
    }

    private func health(navigationFinished: Bool, milestones: UInt = 0, timing: WKPageLoadTiming? = nil) -> BreakageSignalsTabExtension.RenderHealth {
        BreakageSignalsTabExtension.renderHealth(navigationFinished: navigationFinished, renderMilestones: milestones, timing: timing)
    }

    // MARK: - Blank page

    func testBlankPageNotFlaggedBeforeNavigationFinishes() {
        // Still loading: nothing painted yet, but that is not breakage.
        XCTAssertFalse(health(navigationFinished: false).blankPage)
    }

    func testBlankPageFlaggedWhenFinishedWithNoPaintAndNoTiming() {
        XCTAssertTrue(health(navigationFinished: true).blankPage)
    }

    func testNotBlankWhenMeaningfulPaintMilestoneFired() {
        XCTAssertFalse(health(navigationFinished: true, milestones: firstMeaningfulPaint).blankPage)
    }

    func testNotBlankWhenVisuallyNonEmptyMilestoneFired() {
        XCTAssertFalse(health(navigationFinished: true, milestones: firstVisuallyNonEmptyLayout).blankPage)
    }

    func testNonContentMilestoneDoesNotCountAsRendered() {
        // FirstLayout alone is layout, not paint — a finished page with only this is still blank.
        XCTAssertTrue(health(navigationFinished: true, milestones: firstLayout).blankPage)
    }

    func testNotBlankWhenTimingReportsMeaningfulPaint() {
        let timing = makeTiming(firstMeaningfulPaint: t)
        XCTAssertFalse(health(navigationFinished: true, timing: timing).blankPage)
    }

    func testNotBlankWhenTimingReportsFirstVisualLayout() {
        let timing = makeTiming(firstVisualLayout: t)
        XCTAssertFalse(health(navigationFinished: true, timing: timing).blankPage)
    }

    // MARK: - Unfinished subresources

    func testSubresourcesUnfinishedWhenDocumentFinishedButSubresourcesPending() {
        let timing = makeTiming(documentFinishedLoading: t, allSubresourcesFinishedLoading: nil)
        XCTAssertTrue(health(navigationFinished: true, timing: timing).subresourcesUnfinished)
    }

    func testSubresourcesNotFlaggedWhenAllFinished() {
        let timing = makeTiming(documentFinishedLoading: t, allSubresourcesFinishedLoading: t)
        XCTAssertFalse(health(navigationFinished: true, timing: timing).subresourcesUnfinished)
    }

    func testSubresourcesNotFlaggedWithoutDocumentFinishedBaseline() {
        // No document-finished timestamp → no basis to claim subresources are stuck.
        let timing = makeTiming(documentFinishedLoading: nil, allSubresourcesFinishedLoading: nil)
        XCTAssertFalse(health(navigationFinished: true, timing: timing).subresourcesUnfinished)
    }

    // MARK: - Anomaly composition

    func testHealthyPageHasNoAnomaly() {
        let timing = makeTiming(firstMeaningfulPaint: t, documentFinishedLoading: t, allSubresourcesFinishedLoading: t)
        let result = health(navigationFinished: true, milestones: firstMeaningfulPaint, timing: timing)
        XCTAssertFalse(result.blankPage)
        XCTAssertFalse(result.subresourcesUnfinished)
        XCTAssertFalse(result.anomaly)
    }

    func testAnomalyTrueWhenEitherFlagSet() {
        XCTAssertTrue(health(navigationFinished: true).anomaly) // blank
        let timing = makeTiming(firstMeaningfulPaint: t, documentFinishedLoading: t, allSubresourcesFinishedLoading: nil)
        XCTAssertTrue(health(navigationFinished: true, milestones: firstMeaningfulPaint, timing: timing).anomaly) // subresources
    }

    // MARK: - Network-connection-integrity failures

    func testIntegrityFailuresNotAnomalousWhenNoneRecorded() {
        XCTAssertFalse(BreakageSignalsTabExtension.IntegrityFailures().isAnomalous)
    }

    func testIntegrityFailuresAnomalousAfterRecording() {
        let group = BreakageSignalsTabExtension.IntegrityFailures()
        group.record(domain: "example.com", max: 200)
        XCTAssertTrue(group.isAnomalous)
        XCTAssertEqual(group.total, 1)
        XCTAssertEqual(group.domains["example.com"], 1)
    }

    func testIntegrityFailuresCountPerDomainButTotalKeepsCounting() {
        let group = BreakageSignalsTabExtension.IntegrityFailures()
        group.record(domain: "a.com", max: 1)
        group.record(domain: "a.com", max: 1)
        group.record(domain: "b.com", max: 1) // domain map is full, but total still increments
        XCTAssertEqual(group.total, 3)
        XCTAssertEqual(group.domains["a.com"], 2)
        XCTAssertNil(group.domains["b.com"])
    }

    // MARK: - Storage-access prompts / quirks

    func testStoragePromptWithoutQuirkIsNotAnomalous() {
        let group = BreakageSignalsTabExtension.StorageAccessPrompts()
        group.record(subFrameDomain: "tracker.example", quirk: false, max: 200)
        XCTAssertFalse(group.isAnomalous) // a plain prompt is not, by itself, breakage
        XCTAssertEqual(group.prompts, 1)
        XCTAssertEqual(group.quirks, 0)
        XCTAssertTrue(group.quirkDomains.isEmpty)
    }

    func testStorageQuirkIsAnomalousAndRecordsDomain() {
        let group = BreakageSignalsTabExtension.StorageAccessPrompts()
        group.record(subFrameDomain: "fragile.example", quirk: true, max: 200)
        XCTAssertTrue(group.isAnomalous)
        XCTAssertEqual(group.prompts, 1)
        XCTAssertEqual(group.quirks, 1)
        XCTAssertEqual(group.quirkDomains["fragile.example"], 1)
    }

    func testStorageMixedPromptsCountSeparately() {
        let group = BreakageSignalsTabExtension.StorageAccessPrompts()
        group.record(subFrameDomain: "a.example", quirk: false, max: 200)
        group.record(subFrameDomain: "b.example", quirk: true, max: 200)
        group.record(subFrameDomain: "b.example", quirk: true, max: 200)
        XCTAssertEqual(group.prompts, 3)
        XCTAssertEqual(group.quirks, 2)
        XCTAssertEqual(group.quirkDomains["b.example"], 2)
        XCTAssertNil(group.quirkDomains["a.example"])
    }
}
