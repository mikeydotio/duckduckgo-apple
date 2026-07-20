//
//  TabURLInterceptorTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyConfig
import Subscription
import SubscriptionTestingUtilities
import AIChat
@testable import DuckDuckGo

/// - Important: This suite must never emit to or observe on `NotificationCenter.default`.
///   `TabURLInterceptorDefault` posts `.urlInterceptSubscription` / `.urlInterceptAIChat`
///   notifications that `MainViewController` subscribes to on `.default`; if a `MainViewController`
///   instance from another test is still alive in the shared XCTest host process, a notification
///   posted here can reach it and trip an unrelated navigation-invariant assertion, crashing the
///   whole test host (#15). Every test must construct its `TabURLInterceptorDefault` and bind its
///   `expectation(forNotification:)` calls to the private `notificationCenter` below — never `.default`.
class TabURLInterceptorDefaultTests: XCTestCase {

    private var mockInternalUserStoring = MockInternalUserStoring()
    private var mockAIChatFullModeFeature: MockAIChatFullModeFeatureProviding!
    private var notificationCenter: NotificationCenter!

    var urlInterceptor: TabURLInterceptorDefault!

    override func setUp() {
        super.setUp()
        mockInternalUserStoring.isInternalUser = false
        mockAIChatFullModeFeature = MockAIChatFullModeFeatureProviding()
        notificationCenter = NotificationCenter()
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(internalUserDecider: DefaultInternalUserDecider(store: mockInternalUserStoring)),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  notificationCenter: notificationCenter)
    }

    override func tearDown() {
        urlInterceptor = nil
        notificationCenter = nil
        super.tearDown()
    }
    
    func testAllowsNavigationForNonDuckDuckGoDomain() {
        let url = URL(string: "https://www.example.com")!
        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
    }
    
    func testAllowsNavigationForUninterceptedDuckDuckGoPath() {
        let url = URL(string: "https://duckduckgo.com/about")!
        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
    }
    
    func testNotificationForInterceptedSubscriptionPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        let url = URL(string: "https://duckduckgo.com/subscriptions")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // Fail if no note is posted
        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testNotificationForInterceptedLegacyProPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        let url = URL(string: "https://duckduckgo.com/pro")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testNotificationForInterceptedLegacyProPlansPath() {
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        let url = URL(string: "https://duckduckgo.com/pro/plans")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testWhenURLIsSubscriptionAndHasOriginQueryParameterThenNotificationUserInfoHasOriginSet() throws {
        // GIVEN
        var capturedNotification: Notification?
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: { notification in
            capturedNotification = notification
            return true
        })
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions?origin=test_origin"))
        
        // WHEN
        _ = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        waitForExpectations(timeout: 1)
        let interceptedURLComponents = try XCTUnwrap(capturedNotification?.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents)
        let originQueryItem = try XCTUnwrap(interceptedURLComponents.queryItems?.first { $0.name == AttributionParameter.origin })
        XCTAssertEqual(originQueryItem.value, "test_origin")
    }

    func testWhenURLIsSubscriptionAndDoesNotHaveOriginQueryParameterThenNotificationUserInfoDoesNotHaveOriginSet() throws {
        // GIVEN
        var capturedNotification: Notification?
        _ = self.expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: { notification in
            capturedNotification = notification
            return true
        })
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/subscriptions"))

        // WHEN
        _ = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        waitForExpectations(timeout: 1)
        let interceptedURLComponents = try XCTUnwrap(capturedNotification?.userInfo?[TabURLInterceptorParameter.interceptedURLComponents] as? URLComponents)
        let originQueryItem = interceptedURLComponents.queryItems?.first { $0.name == AttributionParameter.origin }
        XCTAssertNil(originQueryItem)
    }

    func testAllowsNavigationForNonAIChatURL() {
        let url = URL(string: "https://www.example.com")!
        XCTAssertTrue(urlInterceptor.allowsNavigatingTo(url: url))
    }

    func testNotificationForInterceptedAIChatPathWhenFeatureFlagIsOn() {
        mockAIChatFullModeFeature.isAvailable = false
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  isIpad: false,
                                                  notificationCenter: notificationCenter)

        _ = self.expectation(forNotification: .urlInterceptAIChat, object: nil, notificationCenter: notificationCenter, handler: nil)

        let url = URL(string: "https://duckduckgo.com/?ia=chat")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertFalse(canNavigate)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Notification expectation failed: \(error)")
            }
        }
    }

    func testDoesNotAllowNavigationForAIChatPath() {
        mockAIChatFullModeFeature.isAvailable = false
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  isIpad: false,
                                                  notificationCenter: notificationCenter)

        let url = URL(string: "https://duckduckgo.com/?ia=chat")!
        XCTAssertFalse(urlInterceptor.allowsNavigatingTo(url: url))
    }

    func testAllowsNavigationAndDoesNotPostNotificationForAIChatPathOnIPad() {
        // GIVEN: on iPad, AIChat interception is intentionally skipped (TabURLInterceptor.swift)
        // regardless of the AIChatFullMode feature flag, since iPad has its own AIChat surface.
        mockAIChatFullModeFeature.isAvailable = false
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  isIpad: true,
                                                  notificationCenter: notificationCenter)

        let notificationExpectation = expectation(forNotification: .urlInterceptAIChat, object: nil, notificationCenter: notificationCenter, handler: nil)
        notificationExpectation.isInverted = true

        let url = URL(string: "https://duckduckgo.com/?ia=chat")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        XCTAssertTrue(canNavigate)

        waitForExpectations(timeout: 0.5) { error in
            if let error = error {
                XCTFail("Notification should not be posted on iPad: \(error)")
            }
        }
    }

    func testAllowsNavigationForAIChatPathWhenFullModeFeatureIsAvailable() {
        // Given
        mockAIChatFullModeFeature.isAvailable = true
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  notificationCenter: notificationCenter)

        // When
        let url = URL(string: "https://duckduckgo.com/?ia=chat")!
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)
        
        // Then
        XCTAssertTrue(canNavigate)
    }
    
    func testDoesNotPostNotificationForAIChatPathWhenFullModeFeatureIsAvailable() {
        // Given
        mockAIChatFullModeFeature.isAvailable = true
        urlInterceptor = TabURLInterceptorDefault(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                                  canPurchase: { true },
                                                  aichatFullModeFeature: mockAIChatFullModeFeature,
                                                  notificationCenter: notificationCenter)

        let notificationExpectation = expectation(forNotification: .urlInterceptAIChat, object: nil, notificationCenter: notificationCenter, handler: nil)
        notificationExpectation.isInverted = true
        
        // When
        let url = URL(string: "https://duckduckgo.com/?ia=chat")!
        _ = urlInterceptor.allowsNavigatingTo(url: url)
        
        // Then
        waitForExpectations(timeout: 0.5) { error in
            if let error = error {
                XCTFail("Notification should not be posted: \(error)")
            }
        }
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsDisabledThenNavigationIsNotIntercepted() async throws {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)
        notificationExpectation.isInverted = true

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions")!
        mockInternalUserStoring.isInternalUser = false

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertTrue(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testWhenURLBelongsToTestDomainAndInternalModeIsEnabledThenRedirectTriggers() async throws {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testNotificationForInterceptedSubscriptionPlansPath() async {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        // GIVEN
        let url = URL(string: "https://duck.co/subscriptions/plans")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    func testNotificationForInterceptedSubscriptionUpgradePath() async {
        let notificationExpectation = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)

        // GIVEN
        let url = URL(string: "https://duckduckgo.com/subscriptions/plans?tier=pro")!
        mockInternalUserStoring.isInternalUser = true

        // WHEN
        let canNavigate = urlInterceptor.allowsNavigatingTo(url: url)

        // THEN
        XCTAssertFalse(canNavigate)
        await fulfillment(of: [notificationExpectation], timeout: 0.5)
    }

    /// Regression for #15: subscription interception must post only to the injected
    /// `notificationCenter`, never `NotificationCenter.default`, so a leaked `MainViewController`
    /// subscribed on `.default` can't receive it and trip the `MainViewController+Segues` assertion.
    func testSubscriptionInterceptionDoesNotPostToDefaultNotificationCenter() {
        let onPrivateCenter = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: notificationCenter, handler: nil)
        let onDefaultCenter = expectation(forNotification: .urlInterceptSubscription, object: nil, notificationCenter: .default, handler: nil)
        onDefaultCenter.isInverted = true

        let url = URL(string: "https://duckduckgo.com/subscriptions")!
        _ = urlInterceptor.allowsNavigatingTo(url: url)

        wait(for: [onPrivateCenter], timeout: 1)
        wait(for: [onDefaultCenter], timeout: 0.5)
    }

}
