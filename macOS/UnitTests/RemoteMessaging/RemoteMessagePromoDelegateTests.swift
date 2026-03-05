//
//  RemoteMessagePromoDelegateTests.swift
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
import PersistenceTestingUtils
import RemoteMessaging
import RemoteMessagingTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class RemoteMessagePromoDelegateTests: XCTestCase {

    private var model: ActiveRemoteMessageModel!
    private var store: MockRemoteMessagingStore!
    private var ntpMessage: RemoteMessageModel!
    private var tabBarMessage: RemoteMessageModel!

    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        store = MockRemoteMessagingStore()
        ntpMessage = RemoteMessageModel(
            id: "ntp-1",
            surfaces: .newTabPage,
            content: .small(titleText: "test", descriptionText: "desc"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        tabBarMessage = RemoteMessageModel(
            id: "tabbar-1",
            surfaces: .tabBar,
            content: .bigSingleAction(
                titleText: "Help Us Improve!",
                descriptionText: "Description",
                placeholder: .announce,
                imageUrl: nil,
                primaryActionText: "Test",
                primaryAction: .survey(value: "www.survey.com")
            ),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
    }

    override func tearDown() {
        model = nil
        store = nil
        ntpMessage = nil
        tabBarMessage = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func makeModel() -> ActiveRemoteMessageModel {
        ActiveRemoteMessageModel(
            remoteMessagingStore: self.store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
    }

    private func makeDependencies(activeRemoteMessageModel: ActiveRemoteMessageModel) -> PromoDependencies {
        PromoDependencies(
            keyValueStore: InMemoryThrowingKeyValueStore(),
            isExternallyActivated: false,
            activeRemoteMessageModel: activeRemoteMessageModel
        )
    }

    // MARK: - Delegate Eligibility Tests

    func testWhenNTPMessageExistsThenNTPDelegateIsEligible() {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        XCTAssertTrue(delegate.isEligible)
    }

    func testWhenNoMessageExistsThenDelegateIsNotEligible() {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)

        XCTAssertFalse(delegate.isEligible)
    }

    func testWhenTabBarMessageExistsThenTabBarDelegateIsEligible() {
        store.scheduledRemoteMessage = tabBarMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .tabBar)

        XCTAssertTrue(delegate.isEligible)
    }

    func testWhenRefreshEligibilityCalledThenReflectsCurrentMessageState() {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)
        XCTAssertFalse(delegate.isEligible)

        store.scheduledRemoteMessage = ntpMessage
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        let expectation = expectation(description: "Model updated")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        delegate.refreshEligibility()
        XCTAssertTrue(delegate.isEligible)
    }

    // MARK: - Show/Dismiss Flow Tests

    func testWhenUserDismissesThenShowReturnsIgnoredWithZeroCooldown() async {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)
        let record = PromoHistoryRecord(id: "remote-message-ntp")

        let task = Task { @MainActor in
            await delegate.show(history: record)
        }

        delegate.userDidDismiss()
        store.scheduledRemoteMessage = nil
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        let result = await task.value
        if case .ignored(cooldown: let interval?) = result {
            XCTAssertEqual(interval, 0)
        } else {
            XCTFail("Expected .ignored(cooldown: 0), got \(result)")
        }
    }

    func testWhenNaturalDisappearanceThenEligibilityUpdatesToFalse() {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)
        XCTAssertTrue(delegate.isEligible)

        let expectation = expectation(description: "Eligibility becomes false")
        var receivedEligible = false
        delegate.isEligiblePublisher
            .dropFirst()
            .sink { eligible in
                receivedEligible = eligible
                if !eligible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        store.scheduledRemoteMessage = nil
        NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(receivedEligible)
        XCTAssertFalse(delegate.isEligible)
    }

    func testWhenHideCalledDuringActiveShowThenReturnsNoChange() async {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)
        let record = PromoHistoryRecord(id: "remote-message-ntp")

        let task = Task { @MainActor in
            await delegate.show(history: record)
        }

        await MainActor.run {
            delegate.hide()
        }

        let result = await task.value
        if case .noChange = result {
            // Expected
        } else {
            XCTFail("Expected .noChange, got \(result)")
        }
    }

    // MARK: - Factory Configuration Tests

    func testWhenMakePromosCalledThenReturnsTwoPromosWithCorrectConfiguration() async {
        store.scheduledRemoteMessage = nil
        model = makeModel()
        let dependencies = makeDependencies(activeRemoteMessageModel: model)
        let promos = await PromoServiceFactory.makeRemoteMessagePromos(dependencies: dependencies)

        XCTAssertEqual(promos.count, 2)

        let ntpPromo = promos.first { $0.id == "remote-message-ntp" }
        let tabBarPromo = promos.first { $0.id == "remote-message-tabbar" }
        XCTAssertNotNil(ntpPromo)
        XCTAssertNotNil(tabBarPromo)

        for promo in promos {
            XCTAssertEqual(promo.triggers, Set([.remoteMessageChanged, .appLaunched]))
            XCTAssertEqual(promo.initiated, .app)
            XCTAssertEqual(promo.promoType.severity, .medium)
            XCTAssertFalse(promo.respectsGlobalCooldown)
            XCTAssertTrue(promo.setsGlobalCooldown)
            XCTAssertNotNil(promo.delegate)
        }

        XCTAssertEqual(ntpPromo?.context, .newTabPage)
        XCTAssertEqual(tabBarPromo?.context, .global)

        XCTAssertTrue(ntpPromo?.coexistingPromoIDs.contains("remote-message-tabbar") ?? false, "rmf-ntp must coexist with rmf-tabbar")
        XCTAssertTrue(tabBarPromo?.coexistingPromoIDs.contains("remote-message-ntp") ?? false, "rmf-tabbar must coexist with rmf-ntp")
    }

    // MARK: - Factory Callback Behavior Tests

    func testWhenCallbackInvokedWithOnlyNTPMessage_ThenNTPDelegateShowReturnsIgnoredWithZeroCooldown() async {
        store.scheduledRemoteMessage = ntpMessage
        model = makeModel()
        let dependencies = makeDependencies(activeRemoteMessageModel: model)
        let promos = await PromoServiceFactory.makeRemoteMessagePromos(dependencies: dependencies)

        guard let ntpDelegate = promos.first(where: { $0.id == "remote-message-ntp" })?.delegate as? RemoteMessagePromoDelegate else {
            XCTFail("NTP delegate should be a RemoteMessagePromoDelegate")
            return
        }

        let record = PromoHistoryRecord(id: "remote-message-ntp")
        let task = Task { @MainActor in
            await ntpDelegate.show(history: record)
        }

        await MainActor.run {
            model.onRemoteMessageDismissedByUser?()
            store.scheduledRemoteMessage = nil
            NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        }

        let result = await task.value
        if case .ignored(cooldown: let interval?) = result {
            XCTAssertEqual(interval, 0)
        } else {
            XCTFail("Expected .ignored(cooldown: 0), got \(result)")
        }
    }

    func testWhenCallbackInvokedWithOnlyTabBarMessage_ThenTabBarDelegateShowReturnsIgnoredWithZeroCooldown() async {
        store.scheduledRemoteMessage = tabBarMessage
        model = makeModel()
        let dependencies = makeDependencies(activeRemoteMessageModel: model)
        let promos = await PromoServiceFactory.makeRemoteMessagePromos(dependencies: dependencies)

        guard let tabBarDelegate = promos.first(where: { $0.id == "remote-message-tabbar" })?.delegate as? RemoteMessagePromoDelegate else {
            XCTFail("Tab bar delegate should be a RemoteMessagePromoDelegate")
            return
        }

        let record = PromoHistoryRecord(id: "remote-message-tabbar")
        let task = Task { @MainActor in
            await tabBarDelegate.show(history: record)
        }

        await MainActor.run {
            model.onRemoteMessageDismissedByUser?()
            store.scheduledRemoteMessage = nil
            NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        }

        let result = await task.value
        if case .ignored(cooldown: let interval?) = result {
            XCTAssertEqual(interval, 0)
        } else {
            XCTFail("Expected .ignored(cooldown: 0), got \(result)")
        }
    }

    func testWhenCallbackInvokedWithMessageOnBothSurfaces_ThenBothDelegatesShowReturnIgnoredWithZeroCooldown() async {
        let bothSurfacesMessage = RemoteMessageModel(
            id: "both-1",
            surfaces: [.newTabPage, .tabBar],
            content: .small(titleText: "both", descriptionText: "desc"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        store.scheduledRemoteMessage = bothSurfacesMessage
        model = makeModel()
        let dependencies = makeDependencies(activeRemoteMessageModel: model)
        let promos = await PromoServiceFactory.makeRemoteMessagePromos(dependencies: dependencies)

        guard let ntpDelegate = promos.first(where: { $0.id == "remote-message-ntp" })?.delegate as? RemoteMessagePromoDelegate,
              let tabBarDelegate = promos.first(where: { $0.id == "remote-message-tabbar" })?.delegate as? RemoteMessagePromoDelegate else {
            XCTFail("Both delegates should be RemoteMessagePromoDelegate")
            return
        }

        let recordNtp = PromoHistoryRecord(id: "remote-message-ntp")
        let recordTabBar = PromoHistoryRecord(id: "remote-message-tabbar")
        let taskNtp = Task { @MainActor in
            await ntpDelegate.show(history: recordNtp)
        }
        let taskTabBar = Task { @MainActor in
            await tabBarDelegate.show(history: recordTabBar)
        }

        await MainActor.run {
            model.onRemoteMessageDismissedByUser?()
            store.scheduledRemoteMessage = nil
            NotificationCenter.default.post(name: RemoteMessagingStore.Notifications.remoteMessagesDidChange, object: nil)
        }

        let resultNtp = await taskNtp.value
        let resultTabBar = await taskTabBar.value

        if case .ignored(cooldown: let intervalNtp?) = resultNtp {
            XCTAssertEqual(intervalNtp, 0, "NTP delegate should return .ignored(cooldown: 0)")
        } else {
            XCTFail("Expected NTP delegate .ignored(cooldown: 0), got \(resultNtp)")
        }
        if case .ignored(cooldown: let intervalTabBar?) = resultTabBar {
            XCTAssertEqual(intervalTabBar, 0, "Tab bar delegate should return .ignored(cooldown: 0)")
        } else {
            XCTFail("Expected tab bar delegate .ignored(cooldown: 0), got \(resultTabBar)")
        }
    }
}
