//
//  AppUserDefaultsTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Bookmarks
import PrivacyConfig

@testable import DuckDuckGo
@testable import Core

class AppUserDefaultsTests: XCTestCase {

    let testGroupName = "test"
    var internalUserDeciderStore: MockInternalUserStoring!
    var customSuite: UserDefaults!

    override func setUp() {
        super.setUp()
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        internalUserDeciderStore = MockInternalUserStoring()

        // Isolate defaults for UserDefaultsWrapper
        UserDefaults.app = customSuite
    }

    override func tearDown() {
        UserDefaults.app = .standard

        internalUserDeciderStore = nil
        super.tearDown()
    }

    func testWhenLinkPreviewsIsSetThenItIsPersisted() {

        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.longPressPreviews = false
        XCTAssertFalse(appUserDefaults.longPressPreviews)

    }

    func testWhenSettingsIsNewThenDefaultForHideLinkPreviewsIsTrue() {

        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        XCTAssertTrue(appUserDefaults.longPressPreviews)

    }

    func testWhenFavoritesDisplayModeIsSetThenItIsWrittenToTheInjectedBookmarksGroup() {

        // Regression test for a defect where the shared bookmarks app-group
        // suite name was hardcoded to "group.com.duckduckgo.bookmarks" instead
        // of being derived from the build-time group-id prefix, so a forked
        // build renaming that prefix would silently lose app<->widget favorites
        // sharing. Injecting a distinguishable suite name here proves the write
        // path uses the injected value rather than a fixed literal, regardless
        // of what the prefix resolves to in this environment.
        let bookmarksGroupName = "test.bookmarks.\(UUID().uuidString)"
        let bookmarksSuite = UserDefaults(suiteName: bookmarksGroupName)!
        bookmarksSuite.removePersistentDomain(forName: bookmarksGroupName)
        defer { bookmarksSuite.removePersistentDomain(forName: bookmarksGroupName) }

        let appUserDefaults = AppUserDefaults(groupName: testGroupName, bookmarksGroupName: bookmarksGroupName)
        let displayMode = FavoritesDisplayMode.displayUnified(native: .desktop)
        appUserDefaults.favoritesDisplayMode = displayMode

        XCTAssertEqual(bookmarksSuite.string(forKey: "com.duckduckgo.ios.favoritesDisplayMode"), displayMode.description)

    }

    func testWhenAllowUniversalLinksIsSetThenItIsPersisted() {

        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.allowUniversalLinks = false
        XCTAssertFalse(appUserDefaults.allowUniversalLinks)

    }

    func testWhenSettingsIsNewThenDefaultForAllowUniversalLinksIsTrue() {
        
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        XCTAssertTrue(appUserDefaults.allowUniversalLinks)

    }

    func testWhenAutocompleteIsSetThenItIsPersisted() {

        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autocomplete = false
        XCTAssertTrue(!appUserDefaults.autocomplete)

    }

    func testWhenReadingAutocompleteDefaultThenTrueIsReturned() {

        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        XCTAssertTrue(appUserDefaults.autocomplete)

    }
    
    func testWhenCurrentThemeIsSetThenItIsPersisted() {
        
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.currentThemeStyle = .light
        XCTAssertEqual(appUserDefaults.currentThemeStyle, .light)
        
    }
    
    func testWhenReadingCurrentThemeDefaultThenSystemDefaultIsReturned() {
        
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        
        XCTAssertEqual(appUserDefaults.currentThemeStyle, .systemDefault)
    }

    func testDefaultAutofillStateIsFalse() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.featureFlagger = MockFeatureFlagger()
        XCTAssertFalse(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeWhenSavePromptShownThenDefaultAutofillStateIsFalse() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.featureFlagger = MockFeatureFlagger()
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = true

        XCTAssertFalse(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasNotBeenSeenAndIsNotNewInstallThenDefaultAutofillStateIsFalse() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.featureFlagger = MockFeatureFlagger()
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = false
        appUserDefaults.autofillIsNewInstallForOnByDefault = false

        XCTAssertFalse(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasNotBeenSeenAndIsNewInstallAndFeatureFlagDisabledThenDefaultAutofillStateIsFalse() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = false
        appUserDefaults.autofillIsNewInstallForOnByDefault = true
        let featureFlagger = MockFeatureFlagger()
        appUserDefaults.featureFlagger = featureFlagger

        XCTAssertFalse(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasNotBeenSeenAndIsNewInstallAndFeatureFlagEnabledThenDefaultAutofillStateIsTrue() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = false
        appUserDefaults.autofillIsNewInstallForOnByDefault = true
        let featureFlagger = createFeatureFlagger(withFeatureFlagEnabled: .autofillOnByDefault)
        appUserDefaults.featureFlagger = featureFlagger

        XCTAssertTrue(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasBeenSeenThenAutofillCredentialsStaysDisabled() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsEnabled = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = true
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        XCTAssertEqual(appUserDefaults.autofillCredentialsEnabled, false)
    }
    
    func testWhenAutofillCredentialsIsDisabledAndButHasBeenTurnedOnAutomaticallyBeforeThenAutofillCredentialsStaysDisabled() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsEnabled = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = false
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = true
        XCTAssertEqual(appUserDefaults.autofillCredentialsEnabled, false)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasNotBeenSeenAndAllUsersFeatureFlagEnabledThenDefaultAutofillStateIsTrue() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = false
        appUserDefaults.autofillIsNewInstallForOnByDefault = false
        let featureFlagger = createFeatureFlagger(withFeatureFlagEnabled: .autofillOnForExistingUsers)
        appUserDefaults.featureFlagger = featureFlagger

        XCTAssertTrue(appUserDefaults.autofillCredentialsEnabled)
    }

    func testWhenAutofillCredentialsIsDisabledAndHasNotBeenTurnedOnAutomaticallyBeforeAndPromptHasBeenSeenAndAllUsersFeatureFlagEnabledThenDefaultAutofillStateIsFalse() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary = false
        appUserDefaults.autofillCredentialsSavePromptShowAtLeastOnce = true
        appUserDefaults.autofillIsNewInstallForOnByDefault = false
        let featureFlagger = createFeatureFlagger(withFeatureFlagEnabled: .autofillOnForExistingUsers)
        appUserDefaults.featureFlagger = featureFlagger

        XCTAssertFalse(appUserDefaults.autofillCredentialsEnabled)
    }

    func testDefaultCookiePopupPreferenceIsBlockStandard_WhenNotInRollout() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.featureFlagger = MockFeatureFlagger()
        XCTAssertEqual(appUserDefaults.cookiePopupPreference, .default)
        XCTAssertTrue(appUserDefaults.autoconsentEnabled)
    }

    func testDefaultCookiePopupPreferenceIsBlockStandard_WhenInRollout() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        appUserDefaults.featureFlagger = createFeatureFlagger(withFeatureFlagEnabled: .autoconsentOnByDefault)
        XCTAssertEqual(appUserDefaults.cookiePopupPreference, .default)
        XCTAssertTrue(appUserDefaults.autoconsentEnabled)
    }

    func testAutoconsentReadsUserStoredValue_RegardlessOfRolloutState() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        // When setting disabled by user and rollout enabled
        appUserDefaults.autoconsentEnabled = false
        appUserDefaults.featureFlagger = createFeatureFlagger(withFeatureFlagEnabled: .autoconsentOnByDefault)

        XCTAssertEqual(appUserDefaults.cookiePopupPreference, .off)
        XCTAssertFalse(appUserDefaults.autoconsentEnabled)

        // When setting enabled by user and rollout disabled
        appUserDefaults.autoconsentEnabled = true
        appUserDefaults.featureFlagger = MockFeatureFlagger()

        XCTAssertEqual(appUserDefaults.cookiePopupPreference, .default)
        XCTAssertTrue(appUserDefaults.autoconsentEnabled)
    }

    func testWhenMigratingFromExplicitlyDisabledAutoconsentThenPreferenceIsDoNotBlock() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)
        customSuite.set(false, forKey: UserDefaultsWrapper<Bool>.Key.autoconsentEnabled.rawValue)

        XCTAssertEqual(appUserDefaults.cookiePopupPreference, .off)
    }

    func testWhenRefreshButtonPositionIsSetThenItIsPersisted() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        appUserDefaults.currentRefreshButtonPosition = .menu
        XCTAssertEqual(appUserDefaults.currentRefreshButtonPosition, .menu)
    }

    func testWhenReadingRefreshButtonPositionDefaultThenAddressBarIsReturned() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        XCTAssertEqual(appUserDefaults.currentRefreshButtonPosition, .addressBar)
    }

    func testWhenShowTrackersBlockedAnimationIsSetThenItIsPersisted() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        appUserDefaults.showTrackersBlockedAnimation = false
        XCTAssertFalse(appUserDefaults.showTrackersBlockedAnimation)
    }

    func testWhenReadingShowTrackersBlockedAnimationDefaultThenTrueIsReturned() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        XCTAssertTrue(appUserDefaults.showTrackersBlockedAnimation)
    }

    // MARK: - Ad-blocking rollout onboarding default

    func testWhenAdBlockingRolloutInactiveThenOnboardingDefaultsKeepDuckPlayerAtDefaults() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        appUserDefaults.applyAdBlockingRolloutDuckPlayerDefaultsIfNeeded(rolloutActive: false)

        XCTAssertEqual(appUserDefaults.duckPlayerMode, .alwaysAsk)
        XCTAssertEqual(appUserDefaults.duckPlayerNativeYoutubeMode, .ask)
    }

    func testWhenAdBlockingRolloutActiveThenOnboardingDefaultsDisableDuckPlayer() {
        let appUserDefaults = AppUserDefaults(groupName: testGroupName)

        appUserDefaults.applyAdBlockingRolloutDuckPlayerDefaultsIfNeeded(rolloutActive: true)

        XCTAssertEqual(appUserDefaults.duckPlayerMode, .disabled)
        XCTAssertEqual(appUserDefaults.duckPlayerNativeYoutubeMode, .never)
    }

    // MARK: - Mock Creation

    private func mockConfiguration(subfeatureEnabled: Bool) -> PrivacyConfiguration {
        let mockPrivacyConfiguration = MockPrivacyConfiguration()
        mockPrivacyConfiguration.isSubfeatureKeyEnabled = { _, _ in
            return subfeatureEnabled
        }

        return mockPrivacyConfiguration
    }

    private func createFeatureFlagger(withFeatureFlagEnabled featureFlag: FeatureFlag) -> FeatureFlagger {
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags.append(featureFlag)
        return mockFeatureFlagger
    }
}
