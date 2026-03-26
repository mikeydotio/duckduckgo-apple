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

@testable import BrowserServicesKit
import PrivacyConfig
import TrackerRadarKit
import XCTest

/// A1 invariant tests enforcing single-authority and hard-disable gates.
///
/// These tests verify:
/// 1. ContentScopeProperties does not carry trackerData (C-S-S trackerProtection hard-disabled).
/// 2. ContentScope generated source does not contain trackerDetected references (no C-S-S classification path).
/// 3. CTL surrogate gating exists in legacy surrogates path (via source generation).
/// 4. Legacy processRule path is the sole classification authority (via source generation).
/// 5. Dataset contract: Rules.encodedTrackerData uses extractSurrogates.
class ContentBlockingA1InvariantTests: XCTestCase {

    // MARK: - A1 Hard Gate: no trackerData in ContentScopeProperties

    func testWhenContentScopePropertiesIsCreatedThenTrackerDataIsAbsent() throws {
        let properties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: "test",
            messageSecret: "test",
            featureToggles: ContentScopeFeatureToggles.allTogglesOn)

        let encoded = try JSONEncoder().encode(properties)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertNil(json?["trackerData"],
                     "ContentScopeProperties must not contain trackerData in A1. " +
                     "C-S-S trackerProtection is hard-disabled on Apple.")
    }

    // MARK: - A1 Hard Gate: generated ContentScope source has no tracker classification

    func testWhenContentScopeSourceIsGeneratedThenNoTrackerDetectedNotifyExists() throws {
        let mockConfig = MockPrivacyConfigurationManager()
        let properties = ContentScopeProperties(
            gpcEnabled: false,
            sessionKey: "test",
            messageSecret: "test",
            featureToggles: ContentScopeFeatureToggles.allTogglesOn)

        let source = try ContentScopeUserScript.generateSource(
            mockConfig,
            properties: properties,
            scriptContext: .contentScope,
            config: WebkitMessagingConfig(hasModernWebkitAPI: true, secret: "test",
                                          webkitMessageHandlerNames: [], methodName: "test"),
            privacyConfigurationJSONGenerator: nil)

        XCTAssertFalse(source.contains("trackerDetected"),
                       "Generated contentScope source must not contain trackerDetected notification path. " +
                       "C-S-S trackerProtection is removed from Apple platform support in A1.")
    }

    // MARK: - A1 Single-Authority Gate: legacy processRule path exists

    func testWhenContentBlockerRulesSourceIsGeneratedThenProcessRuleIsPresent() throws {
        let mockConfig = MockPrivacyConfiguration(isFeatureKeyEnabled: { _, _ in true },
                                                  trackerAllowlist: .init(entries: [:]))
        let source = try ContentBlockerRulesUserScript.generateSource(privacyConfiguration: mockConfig)

        XCTAssertTrue(source.contains("processRule"),
                      "contentblockerrules.js generated source must contain processRule. " +
                      "This is the sole classification signal path in A1.")
    }

    // MARK: - A1 CTL Parity: surrogates source has CTL gating

    func testWhenSurrogatesSourceIsGeneratedThenCTLSurrogatesListIsPresent() throws {
        let mockConfig = MockPrivacyConfiguration(isFeatureKeyEnabled: { _, _ in true },
                                                  trackerAllowlist: .init(entries: [:]))
        let source = try SurrogatesUserScript.generateSource(
            privacyConfiguration: mockConfig,
            surrogates: "",
            encodedSurrogateTrackerData: nil,
            isDebugBuild: false)

        XCTAssertTrue(source.contains("ctlSurrogates"),
                      "surrogates.js generated source must contain ctlSurrogates list for CTL gating")
        XCTAssertTrue(source.contains("isCTLEnabled"),
                      "surrogates.js generated source must contain isCTLEnabled handler for CTL surrogate gating")
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
}
