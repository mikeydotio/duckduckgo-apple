//
//  NextStepsAdvancedCardOrderingExperiment.swift
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
import Foundation
import NewTabPage
import PrivacyConfig

enum NextStepsAdvancedCardOrderingExperiment {

    private static let experiment = FeatureFlag.nextStepsListAdvancedCardOrdering

    static func hasPreviouslyShownAnyNextStepsCard(persistor: NewTabPageNextStepsCardsPersisting) -> Bool {
        NewTabPageDataModel.CardID.allCases.contains { persistor.timesShown(for: $0) > 0 }
    }

    static func shouldEnroll(persistor: NewTabPageNextStepsCardsPersisting, featureFlagger: FeatureFlagger) -> Bool {
        featureFlagger.allActiveExperiments[experiment.rawValue] == nil && !hasPreviouslyShownAnyNextStepsCard(persistor: persistor)
    }

    static func isAdvancedOrderingEnabled(featureFlagger: FeatureFlagger) -> Bool {
        // Check if the user is already assigned to the experiment treatment cohort.
        // Don't resolve the cohort again because users should not be assigned to the experiment if they have already seen any of the cards.
        guard let cohort = featureFlagger.localOverrides?.experimentOverride(for: experiment) ??
                featureFlagger.allActiveExperiments[experiment.rawValue]?.cohortID else {
            return false
        }
        return cohort == FeatureFlag.NextStepsListAdvancedCardOrderingCohort.treatment.rawValue
    }

    @discardableResult
    static func enrollIfNeeded(persistor: NewTabPageNextStepsCardsPersisting,
                               featureFlagger: FeatureFlagger) -> FeatureFlag.NextStepsListAdvancedCardOrderingCohort? {
        guard shouldEnroll(persistor: persistor, featureFlagger: featureFlagger) else {
            return nil
        }
        return featureFlagger.resolveCohort(for: FeatureFlag.nextStepsListAdvancedCardOrdering) as? FeatureFlag.NextStepsListAdvancedCardOrderingCohort
    }
}
