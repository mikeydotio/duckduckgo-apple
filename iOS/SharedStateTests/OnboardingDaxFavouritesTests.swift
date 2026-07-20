//
//  OnboardingDaxFavouritesTests.swift
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
@testable import DuckDuckGo

@MainActor
final class OnboardingDaxFavouritesTests: XCTestCase {
    private var context: MainViewControllerTestFactory.Context!
    private var sut: MainViewController!

    override func setUp() async throws {
        try await super.setUp()
        context = try await MainViewControllerTestFactory.make()
        sut = context.sut
    }

    override func tearDownWithError() throws {
        context.tearDown()
        context = nil
        sut = nil
        try super.tearDownWithError()
    }

    func testWhenMarkOnboardingSeenIsCalled_ThenSetHasSeenOnboardingTrue() {
        // GIVEN
        context.tutorialSettings.hasSeenOnboarding = false

        // WHEN
        sut.markOnboardingSeen()

        // THEN
        XCTAssertTrue(context.tutorialSettings.hasSeenOnboarding)
    }

    func testWhenHasSeenOnboardingIntroIsCalled_AndHasSeenOnboardingSettingIsTrue_ThenReturnFalse() throws {
        // GIVEN
        sut.markOnboardingSeen()

        // WHEN
        let result = sut.needsToShowOnboardingIntro()

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenHasSeenOnboardingIntroIsCalled_AndHasSeenOnboardingIsFalse_ThenReturnTrue() throws {
        // GIVEN
        context.tutorialSettings.hasSeenOnboarding = false

        // WHEN
        let result = sut.needsToShowOnboardingIntro()

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenAddFavouriteIsCalled_ThenItShouldEnableAddFavouriteFlowOnContextualOnboardingLogic() {
        // GIVEN
        context.contextualOnboardingLogic.canStartFavoriteFlow = true
        XCTAssertFalse(context.contextualOnboardingLogic.didCallEnableAddFavoriteFlow)

        // WHEN
        sut.startAddFavoriteFlow()

        // THEN
        XCTAssertTrue(context.contextualOnboardingLogic.didCallEnableAddFavoriteFlow)
    }

}
