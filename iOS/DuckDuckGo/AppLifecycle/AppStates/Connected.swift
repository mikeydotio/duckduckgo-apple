//
//  Connected.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import Core
import Persistence

/// Represents the state where the scene has been connected and is ready for initial setup.
/// - Usage:
///   - This state is typically associated with the `scene(_:willConnectTo:options:)` method in `SceneDelegate`.
///   - The app transitions to this state after launching, when the scene is first created and attached to the app session.
///   - During this state, initial scene-specific configurations and UI setups should be performed.
///   - As part of this state, the `MainViewController` is set as the `rootViewController` of the scene's `UIWindow`.
/// - Transitions:
///   - `Foreground`: Standard transition when the app completes its launch process and becomes active.
///   - `Background`: Occurs when the app is launched but transitions directly to the background, e.g:
///     - The app is protected by a FaceID lock mechanism (introduced in iOS 18.0). If the user opens the app
///       but does not authenticate and then leaves.
///     - The app is launched by the system for background execution but does not immediately become active.
/// - Notes:
///   - Avoid performing heavy or blocking operations during this phase to ensure smooth app startup.
@MainActor
struct Connected: ConnectedHandling {

    typealias Dependencies = SceneDependencies

    let appDependencies: AppDependencies
    let sceneDependencies: SceneDependencies
    let actionToHandle: AppAction?
    let didFinishLaunchingStartTime: CFAbsoluteTime
    private let lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>

    init(stateContext: Launching.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = stateContext.didFinishLaunchingStartTime
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let (mainCoordinator, sessionID) = Self.mainCoordinator(for: window, appDependencies: appDependencies)
        if let sessionID {
            appDependencies.sceneRegistry.registerTabManager(mainCoordinator.tabManager, forSceneID: sessionID)
        }
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)

        let launchTaskManager = appDependencies.launchTaskManager
        launchTaskManager.register(task: ClearInteractionStateTask(autoClearService: autoClearService,
                                                                   interactionStateSource: mainCoordinator.interactionStateSource,
                                                                   sceneRegistry: appDependencies.sceneRegistry))
        sceneDependencies = SceneDependencies(mainCoordinator: mainCoordinator,
                                              screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)

        configure(window, with: mainCoordinator)
    }

    /// Temporary logic to handle cases where the window is disconnected and later reconnected.
    /// Ensures the main coordinator’s main view controller is reattached to the new window.
    /// This unfortunately happens for iOS 16 and lower. Remove this once we drop support for it.
    init(stateContext: Foreground.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = 0
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let (mainCoordinator, sessionID) = Self.mainCoordinator(for: window, appDependencies: appDependencies)
        if let sessionID {
            appDependencies.sceneRegistry.registerTabManager(mainCoordinator.tabManager, forSceneID: sessionID)
        }
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)
        sceneDependencies = SceneDependencies(mainCoordinator: mainCoordinator,
                                              screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)
        configure(window, with: mainCoordinator)
    }

    /// Temporary logic to handle cases where the window is disconnected and later reconnected.
    /// Ensures the main coordinator’s main view controller is reattached to the new window.
    /// This unfortunately happens for iOS 16 and lower. Remove this once we drop support for it.
    init(stateContext: Background.StateContext, actionToHandle: AppAction?, window: UIWindow,
         lastBackgroundDateStorage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys>) {
        appDependencies = stateContext.appDependencies
        didFinishLaunchingStartTime = 0
        self.actionToHandle = actionToHandle
        self.lastBackgroundDateStorage = lastBackgroundDateStorage

        let (mainCoordinator, sessionID) = Self.mainCoordinator(for: window, appDependencies: appDependencies)
        if let sessionID {
            appDependencies.sceneRegistry.registerTabManager(mainCoordinator.tabManager, forSceneID: sessionID)
        }
        let overlayWindowManager = OverlayWindowManager(window: window,
                                                        appSettings: appDependencies.appSettings,
                                                        voiceSearchHelper: appDependencies.voiceSearchHelper,
                                                        featureFlagger: appDependencies.featureFlagger,
                                                        aiChatSettings: appDependencies.aiChatSettings,
                                                        aiChatAddressBarExperience: mainCoordinator.controller.aiChatAddressBarExperience,
                                                        mobileCustomization: mainCoordinator.controller.mobileCustomization)
        let autoClear = AutoClear(worker: mainCoordinator.controller.fireExecutor)
        let autoClearService = AutoClearService(autoClear: autoClear,
                                                overlayWindowManager: overlayWindowManager,
                                                aiChatSyncCleaner: appDependencies.services.syncService.aiChatSyncCleaner)
        let authenticationService = AuthenticationService(overlayWindowManager: overlayWindowManager)
        let screenshotService = ScreenshotService(window: window, mainViewController: mainCoordinator.controller)
        sceneDependencies = SceneDependencies(mainCoordinator: mainCoordinator,
                                              screenshotService: screenshotService,
                                              authenticationService: authenticationService,
                                              autoClearService: autoClearService)
        configure(window, with: mainCoordinator)
    }

    private func configure(_ window: UIWindow, with mainCoordinator: MainCoordinator) {
        ThemeManager.shared.updateUserInterfaceStyle(window: window)
        window.rootViewController = mainCoordinator.controller
        window.makeKeyAndVisible()
        mainCoordinator.start()
    }

    /// The primary scene (the app's first-ever connected scene, and the only one that can exist
    /// until multi-window is enabled) reuses `appDependencies.mainCoordinator`. Any additional
    /// scene gets its own, independently-tabbed `MainCoordinator` via `makeMainCoordinator`, keyed
    /// by that scene's `UISceneSession.persistentIdentifier`, which is also returned so the caller
    /// can register the coordinator's `tabManager` in `SceneRegistry` (see `allConnectedTabs`).
    private static func mainCoordinator(for window: UIWindow, appDependencies: AppDependencies) -> (MainCoordinator, sessionID: String?) {
        guard let sessionID = window.windowScene?.session.persistentIdentifier else {
            // No scene information available — a bare `UIWindow()` as used in unit tests, or a
            // platform where scenes genuinely don't apply. Always the primary/only coordinator.
            return (appDependencies.mainCoordinator, nil)
        }

        guard !appDependencies.sceneRegistry.isPrimaryScene(sessionID: sessionID) else {
            return (appDependencies.mainCoordinator, sessionID)
        }

        do {
            return (try appDependencies.makeMainCoordinator(sessionID, nil), sessionID)
        } catch {
            // Building a second window's own MainCoordinator failed (e.g. disk pressure). Fail
            // loud via pixel + log, then fall back to the primary coordinator so the window still
            // opens — sharing state with the primary window is a safe degradation, a crash is not.
            Logger.lifecycle.error("🔴 Failed to build MainCoordinator for secondary scene: \(error.localizedDescription, privacy: .public)")
            DailyPixel.fireDailyAndCount(pixel: .secondarySceneMainCoordinatorInitError, error: error)
            return (appDependencies.mainCoordinator, sessionID)
        }
    }

}

extension Connected {

    struct StateContext {

        let didFinishLaunchingStartTime: CFAbsoluteTime
        let appDependencies: AppDependencies
        let sceneDependencies: SceneDependencies

    }

    func makeStateContext(sceneDependencies: SceneDependencies) -> StateContext {
        .init(didFinishLaunchingStartTime: didFinishLaunchingStartTime,
              appDependencies: appDependencies,
              sceneDependencies: sceneDependencies)
    }

    func makeBackgroundState() -> any BackgroundHandling {
        Background(stateContext: makeStateContext(sceneDependencies: sceneDependencies),
                   lastBackgroundDateStorage: lastBackgroundDateStorage)
    }

    func makeForegroundState(actionToHandle: AppAction?) -> any ForegroundHandling {
        Foreground(stateContext: makeStateContext(sceneDependencies: sceneDependencies),
                   actionToHandle: actionToHandle,
                   lastBackgroundDateStorage: lastBackgroundDateStorage)
    }

}
