//
//  AppDependencies.swift
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

import Foundation
import PrivacyConfig

struct AppDependencies {

    /// The primary scene's coordinator — the one built at launch, and the only one that ever
    /// exists until multi-window is enabled. App-global presentation hooks bound once at launch
    /// (sync presenter, remote-messaging navigator, VPN/notification presenters, …) always target
    /// this instance; see `Launching.init()`. Additional scenes get their own coordinator from
    /// `makeMainCoordinator` instead and must not be confused with this one.
    let mainCoordinator: MainCoordinator

    /// Builds an additional scene's own `MainCoordinator` (own tabs, own view controller) from the
    /// same already-built app-global services `mainCoordinator` was built from, keyed by that
    /// scene's `UISceneSession.persistentIdentifier` so its tabs persist independently. Pass `nil`
    /// only for the primary scene (see `mainCoordinator` above) — every other caller must pass a
    /// real scene identifier.
    let makeMainCoordinator: (String?, CFAbsoluteTime?) throws -> MainCoordinator

    let services: AppServices
    let launchTaskManager: LaunchTaskManager
    let launchSourceManager: LaunchSourceManaging
    let aiChatSettings: AIChatSettings
    let featureFlagger: FeatureFlagger
    let voiceSearchHelper: VoiceSearchHelperProtocol
    let appSettings: AppSettings
    let backgroundTaskManager: BackgroundTaskManager
    let sceneRegistry: SceneRegistry

}

struct AppServices {

    let contentBlockingService: ContentBlockingService
    let syncService: SyncService
    let vpnService: VPNService
    let dbpService: DBPService
    let autofillService: AutofillService
    let remoteMessagingService: RemoteMessagingService
    let configurationService: RemoteConfigurationService
    let reportingService: ReportingService
    let subscriptionService: SubscriptionService
    let crashCollectionService: CrashCollectionService
    let maliciousSiteProtectionService: MaliciousSiteProtectionService
    let statisticsService: StatisticsService
    let keyValueFileStoreService: AppKeyValueFileStoreService
    let defaultBrowserPromptService: DefaultBrowserPromptService
    let winBackOfferService: WinBackOfferService
    let systemSettingsPiPTutorialService: SystemSettingsPiPTutorialService
    let inactivityNotificationSchedulerService: InactivityNotificationSchedulerService
    let wideEventService: WideEventService
    let aiChatService: AIChatService

}

struct SceneDependencies {

    /// This scene's own coordinator: `appDependencies.mainCoordinator` for the primary scene,
    /// or a freshly-built, independently-tabbed one for any additional scene. Foreground/Background
    /// must operate on this — not `appDependencies.mainCoordinator` — for anything window-specific
    /// (tab manager, onForeground/onBackground, launch-action routing) so a second window isn't
    /// driven by the first window's browsing state.
    let mainCoordinator: MainCoordinator
    let screenshotService: ScreenshotService
    let authenticationService: AuthenticationService
    let autoClearService: AutoClearService

}
