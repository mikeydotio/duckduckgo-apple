//
//  PromoRegistryTests.swift
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

import PersistenceTestingUtils
import RemoteMessaging
import RemoteMessagingTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PromoRegistryTests: XCTestCase {

    func testWhenPromoServiceCreated_ThenAllStringsAreUnique() async {
        let store = MockRemoteMessagingStore()
        let model = ActiveRemoteMessageModel(
            remoteMessagingStore: store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
        let dependencies = PromoDependencies(
            keyValueStore: InMemoryThrowingKeyValueStore(),
            isExternallyActivated: false,
            activeRemoteMessageModel: model)
        let promoService = PromoServiceFactory.makePromoService(dependencies: dependencies)

        let ids = promoService.promos.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Promo IDs must be unique. Duplicates: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    func testWhenPromoServiceCreated_ThenRMFCoexistenceIsSymmetric() async {
        let store = MockRemoteMessagingStore()
        let model = ActiveRemoteMessageModel(
            remoteMessagingStore: store,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
            openURLHandler: { _ in },
            navigateToFeedbackHandler: { },
            navigateToPIRHandler: { },
            navigateToSoftwareUpdateHandler: { }
        )
        let dependencies = PromoDependencies(
            keyValueStore: InMemoryThrowingKeyValueStore(),
            isExternallyActivated: false,
            activeRemoteMessageModel: model)
        let promoService = PromoServiceFactory.makePromoService(dependencies: dependencies)

        let ntpPromo = promoService.promos.first { $0.id == "remote-message-ntp" }
        let tabBarPromo = promoService.promos.first { $0.id == "remote-message-tabbar" }

        XCTAssertNotNil(ntpPromo)
        XCTAssertNotNil(tabBarPromo)
        XCTAssertTrue(ntpPromo?.coexistingPromoIDs.contains("remote-message-tabbar") ?? false, "remote-message-ntp must coexist with remote-message-tabbar")
        XCTAssertTrue(tabBarPromo?.coexistingPromoIDs.contains("remote-message-ntp") ?? false, "remote-message-tabbar must coexist with remote-message-ntp")
    }
}
