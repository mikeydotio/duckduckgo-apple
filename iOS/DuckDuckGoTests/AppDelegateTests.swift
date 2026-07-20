//
//  AppDelegateTests.swift
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

import Common
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("AppDelegate test-mode detection")
struct AppDelegateTestModeTests {

    /// Pins the linchpin the fix in #16 relies on: hosting `UnitTests.xctest` inside `DuckDuckGo.app`
    /// resolves `AppVersion.runType` to `.unitTests`, independent of any scheme-provided launch argument.
    @Test func unitTestHostResolvesToUnitTestsRunType() {
        #expect(AppVersion.runType == .unitTests)
        #expect(AppVersion.runType.requiresEnvironment == false)
    }

    /// Regression for #16: `iOS Unit Tests.xcscheme` never passes the legacy `"testing"` launch argument,
    /// so `AppDelegate.isTesting` must still resolve `true` in a unit-test host via `AppVersion.runType`
    /// alone — otherwise the real launch/foreground state machine runs and fires live ATB/statistics
    /// network calls that pollute the shared App Group `UserDefaults` suite tests read from.
    @Test func isTestingTrueInUnitTestHost() {
        #expect(AppDelegate.isTesting)
    }

    /// Regression for #19: the same `"testing"`-argument gap in #16 was duplicated at five more
    /// production sites, each re-inlining `ProcessInfo().arguments.contains("testing")`. Those sites
    /// now call the shared `AppVersion.isTesting`, which must resolve `true` here for the same reason
    /// `AppDelegate.isTesting` must.
    @Test func sharedIsTestingHelperTrueInUnitTestHost() {
        #expect(AppVersion.isTesting)
    }

    /// Pins `AppDelegate.isTesting` as a thin delegate to `AppVersion.isTesting` (#19), so the two can
    /// never again drift into the kind of scheme-dependent inconsistency #16/#19 both stemmed from.
    @Test func appDelegateIsTestingDelegatesToSharedHelper() {
        #expect(AppDelegate.isTesting == AppVersion.isTesting)
    }

}
