//
//  SceneRegistry.swift
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

import Foundation

/// Coordinates app-wide service lifecycle across however many scenes (windows) are concurrently connected.
///
/// Before per-scene multi-window support, `SceneDelegate` forwarded `didBecomeActive`/`didEnterBackground`
/// straight through to `AppServices.resume()`/`.suspend()` on its single `AppStateMachine`. With multiple
/// scenes now possible on iPad, resuming/suspending services once per scene would waste work and could
/// double-fire startup/teardown side effects (network activity, timers, pixels) — services must resume
/// exactly once when the **first** scene becomes active, and suspend exactly once when the **last** scene
/// backgrounds.
///
/// `SceneRegistry` is app-global (owned via `AppDependencies`, constructed once in `Launching`) and tracks
/// only an active-scene count; each scene's `Foreground`/`Background` state calls into it from
/// `onTransition()` instead of unconditionally resuming/suspending. With exactly one scene connected (the
/// only configuration possible until `UIApplicationSupportsMultipleScenes` is enabled), every foreground
/// transition is trivially "first active" and every background transition is trivially "last background",
/// so behavior is unchanged from today.
@MainActor
final class SceneRegistry {

    private(set) var activeSceneCount = 0
    private var primarySceneID: String?

    init() {}

    /// Determines whether `sceneID` is the app's **primary** scene — the first one to ever connect
    /// in this process, and the only one that can exist until multi-window is enabled. The primary
    /// scene reuses the app's single, launch-built `MainCoordinator` (and everything bound to it:
    /// sync presenter, remote-messaging navigator, VPN/notification presenters, …); every other
    /// scene gets its own independent `MainCoordinator` — see `AppDependencies.makeMainCoordinator`.
    ///
    /// Idempotent for a given scene: once a scene's ID is recorded as primary, reconnecting that
    /// *same* scene (the iOS 16 disconnect/reconnect recovery path) still reports `true` — it must
    /// not be demoted to "secondary" just because it dropped and rejoined.
    func isPrimaryScene(sessionID: String) -> Bool {
        guard let primarySceneID else {
            self.primarySceneID = sessionID
            return true
        }
        return primarySceneID == sessionID
    }

    /// Call when a scene's state machine transitions into `Foreground`.
    /// - Returns: `true` if this was the transition from zero to one active scenes — i.e. services
    ///   should resume. `false` if another scene was already active.
    @discardableResult
    func sceneDidBecomeActive() -> Bool {
        let wasInactive = activeSceneCount == 0
        activeSceneCount += 1
        return wasInactive
    }

    /// Call when a scene's state machine transitions into `Background`.
    /// - Returns: `true` if this was the transition from one to zero active scenes — i.e. services
    ///   should suspend. `false` if another scene remains active.
    @discardableResult
    func sceneDidEnterBackground() -> Bool {
        precondition(activeSceneCount > 0, "sceneDidEnterBackground() called with no active scenes")
        activeSceneCount -= 1
        return activeSceneCount == 0
    }

}
