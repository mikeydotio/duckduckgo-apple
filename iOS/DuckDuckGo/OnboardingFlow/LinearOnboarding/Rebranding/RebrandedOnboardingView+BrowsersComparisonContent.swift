//
//  RebrandedOnboardingView+BrowsersComparisonContent.swift
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

import SwiftUI
import DuckUI
import Onboarding

// MARK: - Model Mapping

extension RebrandedBrowsersComparisonModel.Feature.Availability {
    func toDisplayStatus() -> RebrandedComparisonTableDisplayModel.Row.AvailabilityStatus {
        switch self {
        case .available:
            return .available(self.image)
        case .partial:
            return .partial(self.image)
        case .unavailable:
            return .unavailable(self.image)
        }
    }
}

extension OnboardingRebranding.OnboardingView {

    struct BrowsersComparisonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        @Binding var showContent: Bool
        private let title: String
        private let setAsDefaultBrowserAction: () -> Void
        private let cancelAction: () -> Void

        init(
            showContent: Binding<Bool>,
            title: String,
            setAsDefaultBrowserAction: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self._showContent = showContent
            self.title = title
            self.setAsDefaultBrowserAction = setAsDefaultBrowserAction
            self.cancelAction = cancelAction
        }

        // MARK: - Display Model Mapping

        private static let comparisonDisplayModel: RebrandedComparisonTableDisplayModel = {
            let header = RebrandedComparisonTableDisplayModel.Header.icons(
                leftIcon: OnboardingRebrandingImages.Comparison.safariIcon,
                rightIcon: OnboardingRebrandingImages.Comparison.ddgIcon
            )

            let rows = RebrandedBrowsersComparisonModel.features.map { feature in
                RebrandedComparisonTableDisplayModel.Row(
                    icon: feature.type.icon,
                    title: feature.type.title,
                    leftStatus: feature.safariAvailability.toDisplayStatus(),
                    rightStatus: feature.ddgAvailability.toDisplayStatus()
                )
            }

            return RebrandedComparisonTableDisplayModel(header: header, rows: rows)
        }()

        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                Text(title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RebrandedBrowsersComparisonTable(
                        displayModel: Self.comparisonDisplayModel,
                        availableFeatureAnimation: .animated(startAnimation: showContent)
                    )

                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: setAsDefaultBrowserAction) {
                            Text(UserText.Onboarding.BrowsersComparison.cta)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        Button(action: cancelAction) {
                            Text(UserText.onboardingSkip)
                        }
                        .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                    }
                }
            }
        }

    }

}
