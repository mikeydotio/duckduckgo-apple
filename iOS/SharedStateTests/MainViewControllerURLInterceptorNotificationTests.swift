//
//  MainViewControllerURLInterceptorNotificationTests.swift
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

/// Regression coverage for #21 — the receiver-side counterpart to
/// `TabURLInterceptorDefaultTests.testSubscriptionInterceptionDoesNotPostToDefaultNotificationCenter`
/// (poster-side, #20).
///
/// - Important: `MainViewController` subscribes to `.urlIntercept*` / DBP / settings-deeplink
///   notifications, and every one of those handlers can end up calling `launchSettings(...)`,
///   whose `doLaunch()` asserts `presentedViewController == nil`
///   (`MainViewController+Segues.swift:524`). If a `MainViewController` built by one test is still
///   alive and subscribed on `NotificationCenter.default` when *any* other test posts one of these
///   notifications to `.default`, that assertion can fire and crash the whole XCTest host process
///   (#15). This suite proves a `MainViewController` built via `MainViewControllerTestFactory`
///   (which — like production — subscribes on an injected, non-`.default` center by default) never
///   reacts to `.default`, no matter which of the four notifications is posted.
@MainActor
final class MainViewControllerURLInterceptorNotificationTests: XCTestCase {

    private var context: MainViewControllerTestFactory.Context!
    private var sut: MainViewController!

    override func setUp() async throws {
        try await super.setUp()
        // The factory's default `notificationCenter` is a private, per-call instance — never
        // `.default` — mirroring how production `MainViewController` is itself constructed
        // (MainCoordinator.swift) with its `notificationCenter` parameter defaulted to `.default`,
        // just isolated the other direction for test hermeticity.
        context = try await MainViewControllerTestFactory.make()
        sut = context.sut
    }

    override func tearDownWithError() throws {
        context.tearDown()
        context = nil
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - Negative sweep: .default must never reach an isolated instance

    func testDoesNotReactToURLInterceptSubscriptionPostedToDefaultCenter() {
        assertNoReaction {
            NotificationCenter.default.post(name: .urlInterceptSubscription, object: nil, userInfo: nil)
        }
    }

    func testDoesNotReactToDataBrokerProtectionOpenSubscriptionFlowPostedToDefaultCenter() {
        assertNoReaction {
            NotificationCenter.default.post(name: .dataBrokerProtectionOpenSubscriptionFlow, object: nil, userInfo: nil)
        }
    }

    func testDoesNotReactToURLInterceptAIChatPostedToDefaultCenter() {
        assertNoReaction {
            NotificationCenter.default.post(name: .urlInterceptAIChat, object: nil, userInfo: nil)
        }
    }

    func testDoesNotReactToSettingsDeepLinkNotificationPostedToDefaultCenter() {
        assertNoReaction {
            NotificationCenter.default.post(name: .settingsDeepLinkNotification, object: nil, userInfo: nil)
        }
    }

    // MARK: - Positive control: the injected center still works (guards against a false-passing negative sweep)

    /// Without this, every negative test above would pass just as well if the subscriptions were
    /// deleted outright — proving nothing about isolation specifically. Posting the same
    /// notification to the *injected* center and observing a reaction is what proves the
    /// subscription is alive and simply not listening on `.default`.
    func testReactsToURLInterceptSubscriptionPostedToInjectedCenter() {
        XCTAssertNil(sut.presentedViewController, "Precondition: sut must not already be presenting anything.")

        let barrier = waitForMainQueueBarrier {
            context.notificationCenter.post(name: .urlInterceptSubscription, object: nil, userInfo: nil)
        }
        wait(for: [barrier], timeout: 2)

        XCTAssertNotNil(sut.presentedViewController, "sut should have launched Settings in response to its own injected center.")
    }

    // MARK: - Helpers

    /// Posts via `post()`, then waits on a barrier block enqueued on the main queue *after* the
    /// post — deterministic because `subscribeToURLInterceptorNotifications()` /
    /// `subscribeToSettingsDeeplinkNotifications()` both `.receive(on: DispatchQueue.main)`, which
    /// under the hood enqueues its delivery via `DispatchQueue.main.async` during the synchronous
    /// `post()` call, i.e. strictly before our barrier. No sleep, no timeout guess for the thing
    /// actually being proven — the barrier firing IS the proof that any reaction has already run.
    private func waitForMainQueueBarrier(post: () -> Void) -> XCTestExpectation {
        let barrier = expectation(description: "main queue barrier after notification post")
        post()
        DispatchQueue.main.async {
            barrier.fulfill()
        }
        return barrier
    }

    private func assertNoReaction(post: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(sut.presentedViewController, "Precondition: sut must not already be presenting anything.", file: file, line: line)

        let barrier = waitForMainQueueBarrier(post: post)
        wait(for: [barrier], timeout: 2)

        XCTAssertNil(sut.presentedViewController,
                     "sut reacted to a notification posted to .default — it must only react on its injected notificationCenter.",
                     file: file, line: line)
    }
}
