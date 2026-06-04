//
//  UnifiedToggleInputFeature.swift
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

import Foundation
import Common
import FoundationExtensions
import Core
import PrivacyConfig

protocol UnifiedToggleInputFeatureProviding {
    var isAvailable: Bool { get }
    /// When true, the UTI hides the Search↔Duck.ai toggle on Duck.ai tabs regardless of the
    /// user's toggle-enabled setting. Backed by `FeatureFlag.aiChatTabHideToggle`.
    ///
    /// No protocol-extension default: every conformer (including test mocks) must declare an
    /// explicit value so test coverage isn't silently masked by a convenient fallback.
    var isToggleHiddenOnDuckAITab: Bool { get }
}

struct UnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {

    private static let isFeatureFlagEnabledKey = "com.duckduckgo.unifiedToggleInput.session.enabled"
    private static let isToggleHiddenOnDuckAITabKey = "com.duckduckgo.unifiedToggleInput.aiChatTabHideToggle.session.enabled"

    private static let controlCohortID = FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue

    private static let nonControlCohortExcludedExperimentIDs: Set<SubfeatureID> = [
        AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue,
        AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue,
    ]

    /// Snapshot the UTI availability decision once per session, and record the sticky grant the first
    /// time the device becomes available. Call early at launch, before any consumer reads `isAvailable` /
    /// `isToggleHiddenOnDuckAITab`.
    ///
    /// A device is available when `unifiedToggleInput` is on AND either it has already been granted UTI
    /// (so it keeps it forever) or `unifiedToggleInputIncludeNewUsers` is still on. "New user" therefore
    /// just means "not yet granted": shipping `unifiedToggleInputIncludeNewUsers {state: "disabled"}` stops
    /// devices that have never been granted — new installs going forward — without revoking it from anyone
    /// who already had it. `unifiedToggleInputIncludeNewUsers` defaults to on in code, so an absent/unfetched
    /// config keeps new users included.
    static func resolve(using featureFlagger: FeatureFlagger,
                        grantStore: UnifiedToggleInputGrantStoring,
                        devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        let gateDecision: Bool
        if !featureFlagger.isFeatureOn(.unifiedToggleInput) {
            gateDecision = false // primary kill switch wins; the sticky grant is deliberately left untouched.
        } else {
            gateDecision = grantStore.hasGrantedUnifiedToggleInput
                || featureFlagger.isFeatureOn(.unifiedToggleInputIncludeNewUsers)
        }

        // Gate the grant only on the device type, which is known at launch. The experiment cohort
        // isn't enrolled this early (onboarding assigns it later), so it stays a live check in
        // `isAvailable` rather than being frozen into the grant here.
        if gateDecision && devicePlatform.isIphone {
            grantStore.recordGrant()
        }

        UserDefaults.app.set(gateDecision, forKey: isFeatureFlagEnabledKey)
        UserDefaults.app.set(featureFlagger.isFeatureOn(.aiChatTabHideToggle), forKey: isToggleHiddenOnDuckAITabKey)
    }

    /// Device/cohort eligibility applied live at read time, and again when deciding whether to record a
    /// grant. UTI is iPhone-only and excludes non-control cohorts of the Duck.ai onboarding experiments.
    private static func isDeviceEligible(featureFlagger: FeatureFlagger, devicePlatform: DevicePlatformProviding.Type) -> Bool {
        devicePlatform.isIphone && !isInExcludedExperimentCohort(featureFlagger)
    }

    private static func isInExcludedExperimentCohort(_ featureFlagger: FeatureFlagger) -> Bool {
        nonControlCohortExcludedExperimentIDs.contains { experimentID in
            guard let cohortID = featureFlagger.allActiveExperiments[experimentID]?.cohortID else {
                return false
            }
            return cohortID != controlCohortID
        }
    }

    private let featureFlagger: FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
    }

    private var isGateDecisionEnabled: Bool {
        UserDefaults.app.bool(forKey: Self.isFeatureFlagEnabledKey)
    }

    var isAvailable: Bool {
        isGateDecisionEnabled && Self.isDeviceEligible(featureFlagger: featureFlagger, devicePlatform: devicePlatform)
    }

    var isToggleHiddenOnDuckAITab: Bool {
        UserDefaults.app.bool(forKey: Self.isToggleHiddenOnDuckAITabKey)
    }
}
