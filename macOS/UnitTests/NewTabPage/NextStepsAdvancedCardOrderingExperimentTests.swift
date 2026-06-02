//
//  NextStepsAdvancedCardOrderingExperimentTests.swift
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

import FeatureFlags
import NewTabPage
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NextStepsAdvancedCardOrderingExperimentTests: XCTestCase {

    private var persistor: MockNewTabPageNextStepsCardsPersistor!
    private var featureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        persistor = MockNewTabPageNextStepsCardsPersistor()
        featureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        persistor = nil
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenAnyCardWasPreviouslyShownThenShouldEnrollIsFalse() {
        persistor.setTimesShown(1, for: .defaultApp)

        XCTAssertFalse(NextStepsAdvancedCardOrderingExperiment.shouldEnroll(persistor: persistor, featureFlagger: featureFlagger))
    }

    func testWhenEligibleThenShouldEnrollIsTrue() {
        XCTAssertTrue(NextStepsAdvancedCardOrderingExperiment.shouldEnroll(persistor: persistor, featureFlagger: featureFlagger))
    }

    func testWhenTreatmentCohortResolvedThenEnrollIfNeededReturnsTreatmentCohort() {
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.NextStepsListAdvancedCardOrderingCohort.treatment)

        let enrolledCohort = NextStepsAdvancedCardOrderingExperiment.enrollIfNeeded(
            persistor: persistor,
            featureFlagger: featureFlagger
        )

        XCTAssertTrue(enrolledCohort == .treatment)
    }

    func testWhenControlCohortResolvedThenEnrollIfNeededReturnsControlCohort() {
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.NextStepsListAdvancedCardOrderingCohort.control)

        let enrolledCohort = NextStepsAdvancedCardOrderingExperiment.enrollIfNeeded(
            persistor: persistor,
            featureFlagger: featureFlagger
        )

        XCTAssertTrue(enrolledCohort == .control)
    }

    func testWhenAnyCardWasPreviouslyShownThenEnrollIfNeededDoesNotRun() {
        persistor.setTimesShown(1, for: .defaultApp)
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.NextStepsListAdvancedCardOrderingCohort.treatment)

        let enrolledCohort = NextStepsAdvancedCardOrderingExperiment.enrollIfNeeded(
            persistor: persistor,
            featureFlagger: featureFlagger
        )

        XCTAssertNil(enrolledCohort)
    }

    func testWhenTreatmentEnrolledInActiveExperimentsThenIsAdvancedOrderingEnabledIsTrue() {
        featureFlagger.setAdvancedCardOrderingExperimentEnrollment(cohort: .treatment)

        let isAdvancedOrderingEnabled = NextStepsAdvancedCardOrderingExperiment.isAdvancedOrderingEnabled(featureFlagger: featureFlagger)

        XCTAssertTrue(isAdvancedOrderingEnabled)
    }

    func testWhenControlEnrolledInActiveExperimentsThenIsAdvancedOrderingEnabledIsFalse() {
        featureFlagger.setAdvancedCardOrderingExperimentEnrollment(cohort: .control)

        let isAdvancedOrderingEnabled = NextStepsAdvancedCardOrderingExperiment.isAdvancedOrderingEnabled(featureFlagger: featureFlagger)

        XCTAssertFalse(isAdvancedOrderingEnabled)
    }
}

extension MockFeatureFlagger {
    func setAdvancedCardOrderingExperimentEnrollment(cohort: FeatureFlag.NextStepsListAdvancedCardOrderingCohort) {
        self.allActiveExperiments[FeatureFlag.nextStepsListAdvancedCardOrdering.rawValue] = ExperimentData(
            parentID: HtmlNewTabPageSubfeature.nextStepsListAdvancedCardOrdering.parent.rawValue,
            cohortID: cohort.rawValue,
            enrollmentDate: Date()
        )
    }
}
