//
//  NewTabPageOmnibarSubscriptionDialogPresenter.swift
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

import NewTabPage
import PixelKit
import Subscription

/// Presents the shared `AIChatSubscriptionUpsellDialog` for `omnibar_showSubscriptionUpsell`/
/// `omnibar_showSubscriptionUpgrade`. Unlike the address-bar's `AIChatOmnibarSubscriptionUpsellPresenter`,
/// there's no `requiredTier`/`userTier` to infer a flow from — the NTP web app already knows
/// (from a gated model/reasoning-effort's own `upsell` field) whether to subscribe or upgrade, and
/// picks the matching message accordingly. So this presenter just shows the right dialog copy and
/// routes straight to the coordinator, rather than going through `routeGatedSelection`.
@MainActor
final class NewTabPageOmnibarSubscriptionDialogPresenter: NewTabPageOmnibarSubscriptionDialogPresenting {

    private static let featurePage = "duckai"

    private let coordinator: SubscriptionNavigationCoordinator
    private let subscriptionManager: any SubscriptionManager

    init(coordinator: SubscriptionNavigationCoordinator, subscriptionManager: any SubscriptionManager) {
        self.coordinator = coordinator
        self.subscriptionManager = subscriptionManager
    }

    func showSubscriptionUpsellDialog() {
        makeUpsellDialog().show()
    }

    func showSubscriptionUpgradeDialog() {
        makeUpgradeDialog().show()
    }

    /// Split out from `showSubscriptionUpsellDialog()` so tests can exercise the routing
    /// (`onSubscribe`/`onHaveSubscription`) without going through `ModalView.show()`, which needs
    /// a real key window. `omnibar_showSubscriptionUpsell` only fires for a free user (the web
    /// picks this message over the upgrade one based on tier), so title/message stay generic —
    /// matching the address bar's own free-tier dialog, only the primary button follows free-trial
    /// eligibility ("Try for Free" vs "Upgrade"), since the native purchase flow presents the trial
    /// terms itself.
    func makeUpsellDialog() -> AIChatSubscriptionUpsellDialog {
        var dialog = AIChatSubscriptionUpsellDialog()
        dialog.primaryButtonText = subscriptionManager.isUserEligibleForFreeTrial()
            ? UserText.aiChatSubscriptionUpsellDialogTryForFreeButton
            : UserText.aiChatSubscriptionUpsellDialogUpgradeButton
        dialog.onSubscribe = { [coordinator] in
            coordinator.navigateToSubscriptionPurchase(origin: SubscriptionFunnelOrigin.newTabPageOmnibar.rawValue, featurePage: Self.featurePage)
            Self.firePixel(flowType: "purchase")
        }
        dialog.onHaveSubscription = { [coordinator] in
            coordinator.navigateToSubscriptionActivation()
        }
        return dialog
    }

    /// `omnibar_showSubscriptionUpgrade` only fires for an existing Plus subscriber gated to Pro —
    /// matches the address bar's Plus/Pro/internal dialog: distinct title/message, and no "I Have
    /// a Subscription" button since that doesn't apply to someone upgrading an active subscription.
    func makeUpgradeDialog() -> AIChatSubscriptionUpsellDialog {
        var dialog = AIChatSubscriptionUpsellDialog()
        dialog.title = UserText.aiChatSubscriptionUpsellDialogProTitle
        dialog.message = UserText.aiChatSubscriptionUpsellDialogProMessage
        dialog.primaryButtonText = UserText.aiChatSubscriptionUpsellDialogUpgradeButton
        dialog.showsHaveSubscriptionButton = false
        dialog.onSubscribe = { [coordinator] in
            coordinator.navigateToSubscriptionPlans(origin: SubscriptionFunnelOrigin.newTabPageOmnibar.rawValue, featurePage: Self.featurePage)
            Self.firePixel(flowType: "upgrade")
        }
        // Dead in practice since showsHaveSubscriptionButton hides the button, but wired anyway to
        // match the address bar's own dialog builder, which sets it unconditionally.
        dialog.onHaveSubscription = { [coordinator] in
            coordinator.navigateToSubscriptionActivation()
        }
        return dialog
    }

    private static func firePixel(flowType: String) {
        PixelKit.fire(
            AIChatPixel.aiChatNtpSubscriptionUpsellTriggered(flowType: flowType),
            frequency: .dailyAndCount,
            includeAppVersionParameter: true
        )
    }
}
