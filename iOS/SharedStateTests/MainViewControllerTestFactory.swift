//
//  MainViewControllerTestFactory.swift
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
import Persistence
import Bookmarks
import DDGSync
import History
import BrowserServicesKit
import RemoteMessaging
import RemoteMessagingTestsUtils
import DataBrokerProtection_iOS
@testable import Configuration
import Core
import SubscriptionTestingUtilities
import Common
@testable import DuckDuckGo
@testable import PersistenceTestingUtils
import SystemSettingsPiPTutorialTestSupport
import Combine
import PrivacyConfig
import AIChatTestingUtilities

/// Builds a fully-wired, real `MainViewController` for tests that need one, mirroring the
/// production dependency graph with mocks/stubs.
///
/// Extracted so every consumer builds the SUT the same way: the ~70-parameter initializer
/// previously lived inline in a single test file (`OnboardingDaxFavouritesTests`), and a sibling
/// copy of that same construction (in a now-dead test file) silently rotted to a stale
/// pre-restructure initializer signature. See #21.
@MainActor
enum MainViewControllerTestFactory {

    /// A live `MainViewController` plus the observable seams tests commonly assert on.
    @MainActor
    struct Context {
        let sut: MainViewController
        let tutorialSettings: MockTutorialSettings
        let contextualOnboardingLogic: ContextualOnboardingLogicMock
        let onboardingPixelReporter: OnboardingPixelReporterMock
        /// The center `sut` was constructed with. Defaults to a private instance per `make(notificationCenter:)`,
        /// so posting to it (rather than `.default`) is how a test drives `sut`'s notification-based
        /// navigation deterministically without touching any other test's `MainViewController`.
        let notificationCenter: NotificationCenter
        private let window: UIWindow

        fileprivate init(sut: MainViewController,
                          tutorialSettings: MockTutorialSettings,
                          contextualOnboardingLogic: ContextualOnboardingLogicMock,
                          onboardingPixelReporter: OnboardingPixelReporterMock,
                          notificationCenter: NotificationCenter,
                          window: UIWindow) {
            self.sut = sut
            self.tutorialSettings = tutorialSettings
            self.contextualOnboardingLogic = contextualOnboardingLogic
            self.onboardingPixelReporter = onboardingPixelReporter
            self.notificationCenter = notificationCenter
            self.window = window
        }

        /// Dismisses the presented `sut` and tears its window down so it cannot outlive the test —
        /// the leaked-instance hazard #21 exists to close. Call from `tearDownWithError`, before
        /// nil-ing out any reference to this `Context`.
        func tearDown() {
            if sut.presentedViewController != nil {
                sut.dismiss(animated: false)
            }
            window.rootViewController = nil
            window.isHidden = true
        }
    }

    /// Builds a `MainViewController` wired with mocks and presented in a private `UIWindow`.
    ///
    /// - Parameter notificationCenter: the center `sut` subscribes its `urlIntercept*` and
    ///   settings-deeplink notifications on. Defaults to a **private, per-call** instance —
    ///   deliberately never `.default` — so a leaked `sut` can never react to another test's
    ///   `.default`-posted notification. Pass `.default` explicitly only when a test needs to
    ///   prove that isolation itself.
    static func make(notificationCenter: NotificationCenter = NotificationCenter()) async throws -> Context {
        let db = CoreDataDatabase.bookmarksMock
        let bookmarkDatabaseCleaner = BookmarkDatabaseCleaner(bookmarkDatabase: db, errorEvents: nil)
        let keyValueStore: ThrowingKeyValueStoring = MockKeyValueFileStore()
        let mockWebsiteDataManager = MockWebsiteDataManager()
        let dataProviders = SyncDataProviders(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            bookmarksDatabase: db,
            secureVaultFactory: AutofillSecureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter(),
            keyValueStore: keyValueStore,
            settingHandlers: [],
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: SyncErrorHandler(),
            faviconStoring: MockFaviconStore(),
            tld: TLD(),
            featureFlagger: MockFeatureFlagger()
        )

        let homePageConfiguration = HomePageConfiguration(remoteMessagingStore: MockRemoteMessagingStore(), subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        let tabsModel = TabsModel(desktop: true)
        let tutorialSettingsMock = MockTutorialSettings(hasSeenOnboarding: false)
        let contextualOnboardingLogicMock = ContextualOnboardingLogicMock()
        let historyManager = MockHistoryManager()
        let syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        let featureFlagger = MockFeatureFlagger()
        let aiChatSettings = MockAIChatSettingsProvider()
        let freemiumPIRDebugSettings = FreemiumPIRDebugSettings(keyValueStore: keyValueStore)
        let freemiumDBPUserDefaults = try XCTUnwrap(UserDefaults(suiteName: "MainViewControllerTestFactory.\(UUID().uuidString)"))
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(
            userDefaults: freemiumDBPUserDefaults,
            isUserAuthenticated: { false },
            isFreemiumEnabled: { false }
        )
        let fireproofing = MockFireproofing()
        let textZoomCoordinatorProvider = MockTextZoomCoordinatorProvider()
        let subscriptionDataReporter = MockSubscriptionDataReporter()
        let onboardingPixelReporter = OnboardingPixelReporterMock()
        let tabsPersistence = TabsModelPersistence(normalStore: keyValueStore, fireStore: MockKeyValueFileStore(), legacyStore: MockKeyValueStore())
        let variantManager = MockVariantManager()
        let daxDialogsFactory = ContextualDaxDialogFactory(contextualOnboardingLogic: contextualOnboardingLogicMock,
                                                                      contextualOnboardingPixelReporter: onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let mockConfigManager = MockPrivacyConfigurationManager()

        let mockScriptDependencies = DefaultScriptSourceProvider.Dependencies(appSettings: AppSettingsMock(),
                                                                              sync: MockDDGSyncing(),
                                                                              privacyConfigurationManager: mockConfigManager,
                                                                              contentBlockingManager: ContentBlockerRulesManagerMock(),
                                                                              fireproofing: fireproofing,
                                                                              contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                                                                              internalUserDecider: MockInternalUserDecider(),
                                                                              syncErrorHandler: CapturingAdapterErrorHandler(),
                                                                              webExtensionAvailability: nil)

        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)
        let modelProvider = TabsModelProvider(normalTabsModel: tabsModel, fireModeTabsModel: fireModel, persistence: tabsPersistence)
        let tabManager = TabManager(tabsModelProvider: modelProvider,
                                    previewsSource: MockTabPreviewsSource(),
                                    interactionStateSource: nil,
                                    privacyConfigurationManager: mockConfigManager,
                                    bookmarksDatabase: db,
                                    historyManager: historyManager,
                                    syncService: syncService,
                                    userScriptsDependencies: mockScriptDependencies,
                                    contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
                                    subscriptionDataReporter: subscriptionDataReporter,
                                    contextualOnboardingPresenter: contextualOnboardingPresenter,
                                    contextualOnboardingLogic: contextualOnboardingLogicMock,
                                    onboardingPixelReporter: onboardingPixelReporter,
                                    featureFlagger: featureFlagger,
                                    contentScopeExperimentManager: MockContentScopeExperimentManager(),
                                    appSettings: AppDependencyProvider.shared.appSettings,
                                    textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                    autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                                    websiteDataManager: mockWebsiteDataManager,
                                    fireproofing: fireproofing,
                                    favicons: Favicons(),
                                    maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                                    maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                                    featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                    keyValueStore: MockKeyValueFileStore(),
                                    daxDialogsManager: MockDaxDialogsManager(),
                                    aiChatSettings: aiChatSettings,
                                    productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                                    privacyStats: MockPrivacyStats(),
                                    voiceSearchHelper: MockVoiceSearchHelper(),
                                    launchSourceManager: MockLaunchSourceManager(),
                                    darkReaderFeatureSettings: MockDarkReaderFeatureSettings(),
                                    adBlockingAvailability: StubAdBlockingAvailability()
        )
        let fireExecutor = FireExecutor(tabManager: tabManager,
                                        websiteDataManager: mockWebsiteDataManager,
                                        daxDialogsManager: MockDaxDialogsManager(),
                                        syncService: syncService,
                                        bookmarksDatabaseCleaner: bookmarkDatabaseCleaner,
                                        fireproofing: fireproofing,
                                        favicons: Favicons(),
                                        textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                        autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                                        historyManager: historyManager,
                                        featureFlagger: featureFlagger,
                                        privacyConfigurationManager: mockConfigManager,
                                        appSettings: AppSettingsMock(),
                                        aiChatSyncCleaner: MockAIChatSyncCleaning())
        let sut = MainViewController(
            privacyConfigurationManager: mockConfigManager,
            bookmarksDatabase: db,
            historyManager: historyManager,
            homePageConfiguration: homePageConfiguration,
            syncService: syncService,
            syncDataProviders: dataProviders,
            userScriptsDependencies: mockScriptDependencies,
            contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
            appSettings: AppSettingsMock(),
            previewsSource: MockTabPreviewsSource(),
            tabManager: tabManager,
            syncPausedStateManager: CapturingSyncPausedStateManager(),
            subscriptionDataReporter: subscriptionDataReporter,
            contextualOnboardingLogic: contextualOnboardingLogicMock,
            contextualOnboardingPixelReporter: onboardingPixelReporter,
            tutorialSettings: tutorialSettingsMock,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            voiceSearchHelper: MockVoiceSearchHelper(isSpeechRecognizerAvailable: true, voiceSearchEnabled: true),
            featureFlagger: featureFlagger,
            idleReturnEligibilityManager: MockIdleReturnEligibilityManagerForMainVC(),
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(initialOption: .lastUsedTab, keyValueStore: keyValueStore),
            lastTabShortcutAdapter: LastTabShortcutAdapter(keyValueStore: keyValueStore),
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            contentScopeExperimentsManager: MockContentScopeExperimentManager(),
            fireproofing: fireproofing,
            favicons: Favicons(),
            textZoomCoordinatorProvider: textZoomCoordinatorProvider,
            websiteDataManager: mockWebsiteDataManager,
            appDidFinishLaunchingStartTime: nil,
            maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
            aiChatSettings: aiChatSettings,
            aiChatAddressBarExperience: AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                                   aiChatSettings: aiChatSettings),
            themeManager: MockThemeManager(),
            keyValueStore: keyValueStore,
            customConfigurationURLProvider: MockCustomURLProvider(),
            systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager(),
            daxDialogsManager: MockDaxDialogsManager(),
            dbpIOSPublicInterface: nil,
            freemiumPIREligibilityChecker: DefaultFreemiumPIREligibilityChecker(
                featureFlagger: featureFlagger,
                runPrerequisitesDelegate: nil,
                subscriptionAuthenticationStateProvider: SubscriptionManagerMock(),
                freemiumPIRDebugSettings: freemiumPIRDebugSettings
            ),
            freemiumPIRDebugSettings: freemiumPIRDebugSettings,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            profileStateManager: DefaultDBPProfileStateManager(keyValueStore: freemiumDBPUserDefaults),
            launchSourceManager: LaunchSourceManager(),
            winBackOfferVisibilityManager: MockWinBackOfferVisibilityManager(),
            mobileCustomization: MobileCustomization(keyValueStore: MockThrowingKeyValueStore()),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            remoteMessagingPixelReporter: MockRemoteMessagingPixelReporter(),
            productSurfaceTelemetry: MockProductSurfaceTelemetry(),
            fireExecutor: fireExecutor,
            remoteMessagingDebugHandler: MockRemoteMessagingDebugHandler(),
            privacyStats: MockPrivacyStats(),
            whatsNewRepository: MockWhatsNewMessageRepository(scheduledRemoteMessage: nil),
            darkReaderFeatureSettings: MockDarkReaderFeatureSettings(),
            onboardingManager: OnboardingManagerMock(),
            notificationCenter: notificationCenter
        )
        // Force viewDidLoad synchronously and deterministically — it's what wires up
        // subscribeToURLInterceptorNotifications()/subscribeToSettingsDeeplinkNotifications() —
        // before presenting, rather than relying on `present(animated:)` to trigger it as a
        // side effect (which UIKit does not guarantee happens synchronously).
        _ = sut.view

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        // Awaited: `present(animated: false)` still completes asynchronously, and until its
        // completion handler fires, `sut` is "detached" — presenting anything *from* `sut` (which
        // is exactly what the urlIntercept*/settings-deeplink notification handlers under test do)
        // silently no-ops with a `[Presentation] ... whose view is not in the window hierarchy`
        // console warning rather than actually presenting, making `sut.presentedViewController`
        // an unreliable observable if a caller doesn't wait for this first.
        await withCheckedContinuation { continuation in
            window.rootViewController?.present(sut, animated: false) {
                continuation.resume()
            }
        }

        return Context(
            sut: sut,
            tutorialSettings: tutorialSettingsMock,
            contextualOnboardingLogic: contextualOnboardingLogicMock,
            onboardingPixelReporter: onboardingPixelReporter,
            notificationCenter: notificationCenter,
            window: window
        )
    }
}

private final class MockIdleReturnEligibilityManagerForMainVC: IdleReturnEligibilityManaging {
    func isFeatureAvailable() -> Bool { false }
    func isEligibleForNTPAfterIdle() -> Bool { false }
    func effectiveAfterInactivityOption() -> AfterInactivityOption { .lastUsedTab }
    func idleThresholdSeconds() -> Int { 60 }
    func ntpAfterIdleState() -> NTPAfterIdleState { .notEligible }
}
