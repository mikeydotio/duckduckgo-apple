//
//  InterfaceOrientationPolicyTests.swift
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

class InterfaceOrientationPolicyTests: XCTestCase {

    // MARK: - A presented view controller's mask always wins, regardless of idiom or onboarding

    func testWhenPresentedMaskProvidedOnPadThenReturnsPresentedMaskRegardlessOfOnboarding() {
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: true, isShowingOnboarding: false, presentedInterfaceOrientations: [.landscapeLeft]),
            [.landscapeLeft]
        )
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: true, isShowingOnboarding: true, presentedInterfaceOrientations: [.landscapeLeft]),
            [.landscapeLeft]
        )
    }

    func testWhenPresentedMaskProvidedOnPhoneThenReturnsPresentedMaskRegardlessOfOnboarding() {
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: false, isShowingOnboarding: false, presentedInterfaceOrientations: [.landscapeLeft]),
            [.landscapeLeft]
        )
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: false, isShowingOnboarding: true, presentedInterfaceOrientations: [.landscapeLeft]),
            [.landscapeLeft]
        )
    }

    // MARK: - iPad: full orientation support (Split View / Slide Over eligibility), no presented VC

    func testWhenPadAndNotShowingOnboardingThenReturnsAll() {
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: true, isShowingOnboarding: false, presentedInterfaceOrientations: nil),
            .all
        )
    }

    func testWhenPadAndShowingOnboardingThenStillReturnsAll() {
        // The onboarding view controller is not yet the presented VC (or has none of its own mask
        // asserted) — iPad must not narrow here either, or it becomes multitasking-ineligible
        // during the onboarding gap.
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: true, isShowingOnboarding: true, presentedInterfaceOrientations: nil),
            .all
        )
    }

    // MARK: - iPhone: unchanged legacy behavior, no presented VC

    func testWhenPhoneAndNotShowingOnboardingThenReturnsAllButUpsideDown() {
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: false, isShowingOnboarding: false, presentedInterfaceOrientations: nil),
            .allButUpsideDown
        )
    }

    func testWhenPhoneAndShowingOnboardingThenReturnsPortrait() {
        XCTAssertEqual(
            InterfaceOrientationPolicy.supportedOrientations(isPad: false, isShowingOnboarding: true, presentedInterfaceOrientations: nil),
            .portrait
        )
    }

}
