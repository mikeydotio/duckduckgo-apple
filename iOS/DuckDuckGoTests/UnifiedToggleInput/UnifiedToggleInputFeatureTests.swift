//
//  UnifiedToggleInputFeatureTests.swift
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
@testable import Core
import PrivacyConfig

final class UnifiedToggleInputFeatureTests: XCTestCase {

    // MARK: - Mocks

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = false
    }

    private final class MockGrantStore: UnifiedToggleInputGrantStoring {
        private(set) var hasGrantedUnifiedToggleInput: Bool
        private(set) var recordGrantCallCount = 0

        init(hasGranted: Bool = false) {
            hasGrantedUnifiedToggleInput = hasGranted
        }

        func recordGrant() {
            hasGrantedUnifiedToggleInput = true
            recordGrantCallCount += 1
        }
    }

    private enum ExperimentID {
        static let duckAIQuery = AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue
        static let duckAIQueryTrackersDemo = AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        resetSnapshot()
        MockDevicePlatform.isIphone = false
    }

    override func tearDown() {
        resetSnapshot()
        MockDevicePlatform.isIphone = false
        super.tearDown()
    }

    private func resetSnapshot() {
        UnifiedToggleInputFeature.resolve(using: MockFeatureFlagger(enabledFeatureFlags: []),
                                          grantStore: MockGrantStore(),
                                          devicePlatform: MockDevicePlatform.self)
    }

    // MARK: - Helpers

    /// `includeNewUsers` defaults to `true` to mirror the GA "everyone in" state, so the master/device
    /// tests below read like the original (flag on + iPhone ⇒ available).
    private func makeFeature(flagEnabled: Bool,
                             isIphone: Bool,
                             includeNewUsers: Bool = true,
                             granted: Bool = false,
                             activeExperiments: Experiments = [:],
                             grantStore: MockGrantStore? = nil) -> UnifiedToggleInputFeature {
        MockDevicePlatform.isIphone = isIphone
        var flags: [FeatureFlag] = flagEnabled ? [.unifiedToggleInput] : []
        if includeNewUsers {
            flags.append(.unifiedToggleInputIncludeNewUsers)
        }
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: flags)
        featureFlagger.mockActiveExperiments = activeExperiments
        let store = grantStore ?? MockGrantStore(hasGranted: granted)
        UnifiedToggleInputFeature.resolve(using: featureFlagger,
                                          grantStore: store,
                                          devicePlatform: MockDevicePlatform.self)
        return UnifiedToggleInputFeature(featureFlagger: featureFlagger, devicePlatform: MockDevicePlatform.self)
    }

    private func makeExperimentData(for subfeature: AIChatSubfeature, cohortID: CohortID) -> ExperimentData {
        ExperimentData(parentID: subfeature.parent.rawValue,
                       cohortID: cohortID,
                       enrollmentDate: Date())
    }

    // MARK: - Primary flag + device gate

    func test_isAvailable_whenFlagOnAndIphone() {
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOnButNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: false).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffButIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true).isAvailable)
    }

    func test_isNotAvailable_whenFlagOffAndNotIphone() {
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: false).isAvailable)
    }

    // MARK: - Experiment cohort gate

    func test_isAvailable_whenEnrolledInControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue
                                      ),
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue
                                      )
                                  ])

        XCTAssertTrue(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTreatmentACohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentA.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTreatmentBCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentB.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInUnknownNonControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: "treatmentC"
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoTreatmentACohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentA.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoTreatmentBCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentB.rawValue
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isNotAvailable_whenEnrolledInTrackersDemoUnknownNonControlCohort() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQueryTrackersDemo: makeExperimentData(
                                          for: .onboardingDuckAIQueryTrackersDemoExperiment,
                                          cohortID: "treatmentC"
                                      )
                                  ])

        XCTAssertFalse(feature.isAvailable)
    }

    func test_isAvailable_whenTreatmentCohortBelongsToAnotherExperiment() {
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  activeExperiments: [
                                      "otherExperiment": ExperimentData(parentID: "aiChat", cohortID: "treatment", enrollmentDate: Date())
                                  ])

        XCTAssertTrue(feature.isAvailable)
    }

    func test_isAvailable_doesNotResolveExperimentCohort() {
        MockDevicePlatform.isIphone = true
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput, .unifiedToggleInputIncludeNewUsers])
        UnifiedToggleInputFeature.resolve(using: featureFlagger,
                                          grantStore: MockGrantStore(),
                                          devicePlatform: MockDevicePlatform.self)
        let feature = UnifiedToggleInputFeature(featureFlagger: featureFlagger, devicePlatform: MockDevicePlatform.self)

        XCTAssertTrue(feature.isAvailable)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    // MARK: - New-user gate
    //
    // "New user" = a device that has not yet been granted UTI. Availability is
    // `master on AND (granted OR includeNewUsers on)`, then the device/cohort gate.

    func test_whenFlagOff_isNeverAvailable_evenWhenGranted() {
        // The primary kill switch wins over everything, including a prior grant.
        XCTAssertFalse(makeFeature(flagEnabled: false, isIphone: true, includeNewUsers: true, granted: true).isAvailable)
    }

    func test_whenIncludeNewUsersOn_isAvailable() {
        // The no-config GA state: primary flag on, includeNewUsers on. Everyone is in.
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true, includeNewUsers: true, granted: false).isAvailable)
    }

    func test_whenIncludeNewUsersOff_andNotGranted_isNotAvailable() {
        // A device that has never been granted is a "new user" — excluded once the flag is disabled.
        XCTAssertFalse(makeFeature(flagEnabled: true, isIphone: true, includeNewUsers: false, granted: false).isAvailable)
    }

    func test_whenIncludeNewUsersOff_andGranted_staysAvailable() {
        // Grandfathering: an already-granted device keeps UTI even after the flag is disabled.
        XCTAssertTrue(makeFeature(flagEnabled: true, isIphone: true, includeNewUsers: false, granted: true).isAvailable)
    }

    // MARK: - Sticky grant recording

    func test_grantRecorded_whenAvailableWhileIncludingNewUsers() {
        let store = MockGrantStore(hasGranted: false)
        _ = makeFeature(flagEnabled: true, isIphone: true, includeNewUsers: true, grantStore: store)
        XCTAssertTrue(store.hasGrantedUnifiedToggleInput)
        XCTAssertEqual(store.recordGrantCallCount, 1)
    }

    func test_grantNotRecorded_whenIncludeNewUsersOffAndNotGranted() {
        let store = MockGrantStore(hasGranted: false)
        _ = makeFeature(flagEnabled: true, isIphone: true, includeNewUsers: false, grantStore: store)
        XCTAssertFalse(store.hasGrantedUnifiedToggleInput)
        XCTAssertEqual(store.recordGrantCallCount, 0)
    }

    func test_grantNotRecorded_whenFlagOff() {
        let store = MockGrantStore(hasGranted: false)
        _ = makeFeature(flagEnabled: false, isIphone: true, includeNewUsers: true, grantStore: store)
        XCTAssertFalse(store.hasGrantedUnifiedToggleInput)
    }

    func test_grantNotRecorded_whenNotIphone() {
        // An iPad never presents UTI, so it is never granted even when otherwise eligible.
        let store = MockGrantStore(hasGranted: false)
        _ = makeFeature(flagEnabled: true, isIphone: false, includeNewUsers: true, grantStore: store)
        XCTAssertFalse(store.hasGrantedUnifiedToggleInput)
    }

    func test_grantRecordedButNotAvailable_whenInExcludedExperimentCohort() {
        // The cohort isn't part of the grant decision (it isn't settled at launch); it only gates
        // display live in `isAvailable`. So an excluded-cohort device is granted but does not see UTI.
        let store = MockGrantStore(hasGranted: false)
        let feature = makeFeature(flagEnabled: true,
                                  isIphone: true,
                                  includeNewUsers: true,
                                  activeExperiments: [
                                      ExperimentID.duckAIQuery: makeExperimentData(
                                          for: .onboardingDuckAIQueryExperiment,
                                          cohortID: FeatureFlag.DuckAIQueryExperimentCohort.treatmentA.rawValue
                                      )
                                  ],
                                  grantStore: store)
        XCTAssertTrue(store.hasGrantedUnifiedToggleInput, "Grant is gated on device type only, not cohort")
        XCTAssertFalse(feature.isAvailable, "Excluded cohort still suppresses display via the live gate")
    }

    // MARK: - Snapshot semantics

    /// Mid-session flag flips must not change availability. Resolve writes the launch-time decision into
    /// UserDefaults, while readers still apply the device availability gate.
    func test_isAvailable_usesLaunchResolvedFlagSnapshot() {
        MockDevicePlatform.isIphone = true
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.unifiedToggleInput, .unifiedToggleInputIncludeNewUsers])
        UnifiedToggleInputFeature.resolve(using: flagger,
                                          grantStore: MockGrantStore(),
                                          devicePlatform: MockDevicePlatform.self)
        let feature = UnifiedToggleInputFeature(featureFlagger: flagger, devicePlatform: MockDevicePlatform.self)
        XCTAssertTrue(feature.isAvailable, "Precondition: availability is ON after resolve")

        flagger.enabledFeatureFlags = []
        XCTAssertFalse(flagger.isFeatureOn(.unifiedToggleInput),
                       "Sanity: the live flagger now reports the flag as off")
        XCTAssertTrue(feature.isAvailable,
                      "Snapshot must ignore the post-resolve mutation on the same instance")
        XCTAssertTrue(UnifiedToggleInputFeature(featureFlagger: flagger, devicePlatform: MockDevicePlatform.self).isAvailable,
                      "A fresh instance must read the same snapshot, not the mutated live flagger")

        UnifiedToggleInputFeature.resolve(using: flagger,
                                          grantStore: MockGrantStore(),
                                          devicePlatform: MockDevicePlatform.self)
        XCTAssertFalse(feature.isAvailable,
                       "After re-resolving the snapshot must flip — otherwise resolve isn't doing its job")
    }
}
