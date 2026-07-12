//
//  NewTabPageOmnibarSubscriptionDialogPresenterTests.swift
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

import Testing
import Foundation
@testable import DuckDuckGo_Privacy_Browser
import Subscription
import SubscriptionTestingUtilities

@MainActor
struct NewTabPageOmnibarSubscriptionDialogPresenterTests {

    // MARK: - Test Setup

    private func createPresenter() -> (NewTabPageOmnibarSubscriptionDialogPresenter, MockSubscriptionTabsShowing, SubscriptionManagerMock) {
        let mockTabShower = MockSubscriptionTabsShowing()
        let mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionManager.resultURL = URL(string: "https://duckduckgo.com/pro")!
        let coordinator = SubscriptionNavigationCoordinator(
            tabShower: mockTabShower,
            subscriptionManager: mockSubscriptionManager
        )
        let presenter = NewTabPageOmnibarSubscriptionDialogPresenter(coordinator: coordinator)
        return (presenter, mockTabShower, mockSubscriptionManager)
    }

    // MARK: - Upsell (subscribe) dialog

    @Test("Upsell dialog uses subscribe copy and routes to the purchase flow")
    func upsellDialogRoutesToPurchase() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpsellDialog()

        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogSubscribeButton)

        dialog.onSubscribe?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("featurePage=duckai"))
        #expect(url.absoluteString.contains("origin=funnel_newtab_macos__omnibar"))
    }

    @Test("Upsell dialog's 'I Have a Subscription' button routes to activation")
    func upsellDialogHaveSubscriptionRoutesToActivation() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpsellDialog()

        dialog.onHaveSubscription?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        // Activation doesn't append featurePage/origin — only purchase/plans do.
        #expect(!url.absoluteString.contains("featurePage"))
    }

    // MARK: - Upgrade dialog

    @Test("Upgrade dialog uses upgrade copy and routes to the plans flow")
    func upgradeDialogRoutesToPlans() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpgradeDialog()

        #expect(dialog.primaryButtonText == UserText.aiChatSubscriptionUpsellDialogUpgradeButton)

        dialog.onSubscribe?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(url.absoluteString.contains("featurePage=duckai"))
        #expect(url.absoluteString.contains("origin=funnel_newtab_macos__omnibar"))
    }

    @Test("Upgrade dialog's 'I Have a Subscription' button routes to activation")
    func upgradeDialogHaveSubscriptionRoutesToActivation() async throws {
        let (presenter, mockTabShower, _) = createPresenter()
        let dialog = presenter.makeUpgradeDialog()

        dialog.onHaveSubscription?()

        guard case let .subscription(url) = mockTabShower.capturedContent else {
            Issue.record("Expected .subscription tab content")
            return
        }
        #expect(!url.absoluteString.contains("featurePage"))
    }
}
