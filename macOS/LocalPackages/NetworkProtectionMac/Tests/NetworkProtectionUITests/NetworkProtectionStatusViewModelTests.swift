//
//  NetworkProtectionStatusViewModelTests.swift
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

import Combine
import Foundation
import SwiftUI
import VPN
import XCTest
@testable import NetworkProtectionUI
import VPNTestUtils

@MainActor
final class NetworkProtectionStatusViewModelTests: XCTestCase {

    private final class TestTunnelController: TunnelController {
        func start() async {}
        func stop() async {}
        func command(_ command: VPNCommand) async throws {}
        var isConnected: Bool { true }
    }

    func testSubscriptionExpiredViewDidAppear_CallsAppearHandler() {
        var didCallAppearHandler = false
        let model = makeModel(
            subscriptionExpiredViewAppearHandler: { didCallAppearHandler = true }
        )

        model.subscriptionExpiredViewDidAppear()

        XCTAssertTrue(didCallAppearHandler)
    }

    func testSubscriptionExpiredViewDidAppear_DoesNothingWhenHandlerNotProvided() {
        let model = makeModel(subscriptionExpiredViewAppearHandler: nil)

        // Should not crash.
        model.subscriptionExpiredViewDidAppear()
    }

    func testOpenSubscription_WhenSubscribeButtonHandlerProvided_CallsHandler() {
        var didCallSubscribeHandler = false
        let actionHandler = MockVPNUIActionHandler()
        let model = makeModel(
            uiActionHandler: actionHandler,
            subscriptionExpiredViewSubscribeButtonHandler: { didCallSubscribeHandler = true }
        )

        model.openSubscription()

        XCTAssertTrue(didCallSubscribeHandler)
        XCTAssertFalse(actionHandler.showSubscriptionCalled)
    }

    func testOpenSubscription_WhenSubscribeButtonHandlerNotProvided_FallsBackToUIActionHandler() {
        let actionHandler = MockVPNUIActionHandler()
        let expectation = XCTestExpectation(description: "uiActionHandler.showSubscription should be called")
        actionHandler.showSubscriptionCallback = { expectation.fulfill() }
        let model = makeModel(
            uiActionHandler: actionHandler,
            subscriptionExpiredViewSubscribeButtonHandler: nil
        )

        model.openSubscription()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(actionHandler.showSubscriptionCalled)
    }

    // MARK: - Helpers

    private func makeModel(
        uiActionHandler: VPNUIActionHandling = MockVPNUIActionHandler(),
        subscriptionExpiredViewAppearHandler: (() -> Void)? = nil,
        subscriptionExpiredViewSubscribeButtonHandler: (() -> Void)? = nil
    ) -> NetworkProtectionStatusView.Model {
        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let isExtensionUpdateOfferedPublisher = CurrentValuePublisher<Bool, Never>(
            initialValue: false,
            publisher: Just(false).eraseToAnyPublisher()
        )

        return NetworkProtectionStatusView.Model(
            controller: TestTunnelController(),
            onboardingStatusPublisher: Just(OnboardingStatus.completed).eraseToAnyPublisher(),
            statusReporter: MockNetworkProtectionStatusReporter(),
            uiActionHandler: uiActionHandler,
            menuItems: { [] },
            agentLoginItem: nil,
            isExtensionUpdateOfferedPublisher: isExtensionUpdateOfferedPublisher,
            isMenuBarStatusView: false,
            userDefaults: userDefaults,
            locationFormatter: MockVPNLocationFormatter(),
            uninstallHandler: { _ in },
            subscriptionExpiredViewAppearHandler: subscriptionExpiredViewAppearHandler,
            subscriptionExpiredViewSubscribeButtonHandler: subscriptionExpiredViewSubscribeButtonHandler
        )
    }
}
