//
//  AppDelegate.swift
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

import UIKit
import Common

@UIApplicationMain class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Owned here — not by `Launching`, which is rebuilt on every cold start — because it must
    /// survive for the whole process lifetime and be reachable from `didDiscardSceneSessions`
    /// regardless of which lifecycle state the app is currently in.
    let sceneRegistry = SceneRegistry()
    let appStateMachine: AppStateMachine

    override init() {
        appStateMachine = AppStateMachine(initialState: .initializing(Initializing(sceneRegistry: sceneRegistry)))
        super.init()
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    /// See: `Launching.swift`
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // SwiftUI Previews run without the app group container, so skip app initialization to avoid crashing.
        guard AppVersion.runType != .xcPreviews else { return true }

        appStateMachine.handle(.didFinishLaunching(isTesting: Self.isTesting))
        return true
    }

    /// Called when the system permanently discards a scene's session — on iPad, this means the
    /// user closed that window (not just backgrounded it). Cleans up that window's on-disk tabs
    /// and its now-dead `TabManager` entry in `sceneRegistry`, which would otherwise leak the
    /// window's entire object graph (MainCoordinator, TabManager, MainViewController, tabs) for
    /// the rest of the process's lifetime.
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        for session in sceneSessions {
            let sessionID = session.persistentIdentifier
            TabsModelPersistence.deleteFiles(forDiscardedSceneID: sessionID)
            sceneRegistry.unregisterTabManager(forSceneID: sessionID)
        }
    }

}

extension AppDelegate {

    /// Whether the app must skip its real launch/foreground state machine — and the live network,
    /// ATB/statistics, and pixel activity it drives — because it is hosted inside an XCTest unit-test
    /// bundle.
    ///
    /// Delegates to the shared, environment-based `AppVersion.isTesting` (see #16, #19) so the guard
    /// holds no matter which scheme launches the tests, unlike the legacy `"testing"` launch argument
    /// the `iOS Unit Tests` scheme never passes. `.xcPreviews` is already excluded one line above this
    /// property's call site, so `AppVersion.isTesting`'s `.unitTests`-only scoping doesn't change
    /// behavior here.
    static var isTesting: Bool {
        AppVersion.isTesting
    }

}
