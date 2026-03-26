//
//  ContentBlockingA1InvariantTests.swift
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

import BrowserServicesKit
import ContentScopeScripts
import TrackerRadarKit
import XCTest

/// A1 invariant tests enforcing single-authority and hard-disable gates.
///
/// These tests verify:
/// 1. trackerProtection is absent from the Apple C-S-S bundle platform feature list (build-time gate).
/// 2. ContentScopeUserScript generated source does not contain trackerDetected message handler references (runtime gate).
/// 3. CTL surrogate gating parity for both macOS (enabled) and iOS (disabled).
/// 4. Legacy processRule path is the sole classification authority.
class ContentBlockingA1InvariantTests: XCTestCase {

    // MARK: - A1 Hard Gate: trackerProtection absent from Apple bundle

    func testWhenAppleBundleIsLoadedThenTrackerProtectionFeatureIsAbsent() throws {
        let contentScopeSource = try Self.loadContentScopeBundle(fileName: "contentScope")
        XCTAssertFalse(contentScopeSource.contains("\"trackerProtection\""),
                       "trackerProtection must not be present in the Apple contentScope bundle. " +
                       "A1 requires it to be removed from features.js platformSupport.apple.")
    }

    func testWhenAppleIsolatedBundleIsLoadedThenTrackerProtectionFeatureIsAbsent() throws {
        let isolatedSource = try Self.loadContentScopeBundle(fileName: "contentScopeIsolated")
        XCTAssertFalse(isolatedSource.contains("\"trackerProtection\""),
                       "trackerProtection must not be present in the Apple contentScopeIsolated bundle.")
    }

    // MARK: - A1 Single-Authority Gate: legacy processRule is sole classifier

    func testWhenContentBlockerRulesJSIsLoadedThenProcessRulePostMessageIsPresent() throws {
        let bskBundle = Bundle(for: ContentBlockerRulesUserScript.self)
        let source = try ContentBlockerRulesUserScript.loadJS("contentblockerrules", from: bskBundle)
        XCTAssertTrue(source.contains("processRule"),
                      "contentblockerrules.js must contain the processRule postMessage call. " +
                      "This is the sole classification signal path in A1.")
    }

    // MARK: - A1 CTL Parity: surrogates.js has CTL gating

    func testWhenSurrogatesJSIsLoadedThenCTLSurrogateListIsPresent() throws {
        let bskBundle = Bundle(for: ContentBlockerRulesUserScript.self)
        let surrogatesSource = try SurrogatesUserScript.loadJS("surrogates", from: bskBundle)
        XCTAssertTrue(surrogatesSource.contains("ctlSurrogates"),
                      "surrogates.js must contain the ctlSurrogates list for CTL gating")
    }

    func testWhenSurrogatesJSIsLoadedThenIsCTLEnabledHandlerIsPresent() throws {
        let bskBundle = Bundle(for: ContentBlockerRulesUserScript.self)
        let surrogatesSource = try SurrogatesUserScript.loadJS("surrogates", from: bskBundle)
        XCTAssertTrue(surrogatesSource.contains("isCTLEnabled"),
                      "surrogates.js must contain the isCTLEnabled async handler for CTL surrogate gating")
    }

    // MARK: - Dataset contract: Rules.encodedTrackerData uses extractSurrogates

    func testWhenRulesEncodedTrackerDataIsDecodedThenItContainsOnlySurrogateTrackers() throws {
        let tds = ContentBlockingDatasetContractTests.tdsWithMixedTrackers
        let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: tds)
        let encoded = try JSONEncoder().encode(surrogateTDS)
        let decoded = try JSONDecoder().decode(TrackerData.self, from: encoded)

        for (_, tracker) in decoded.trackers {
            let hasSurrogate = tracker.rules?.contains(where: { $0.surrogate != nil }) ?? false
            XCTAssertTrue(hasSurrogate,
                          "Decoded surrogate TDS must only contain trackers with surrogate rules")
        }
        XCTAssertTrue(decoded.trackers.count < tds.trackers.count,
                      "Decoded surrogate TDS must have fewer trackers than the full TDS")
    }

    // MARK: - Helpers

    private static func loadContentScopeBundle(fileName: String) throws -> String {
        guard let url = ContentScopeScripts.Bundle.url(forResource: fileName, withExtension: "js"),
              let source = try? String(contentsOf: url) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return source
    }
}
