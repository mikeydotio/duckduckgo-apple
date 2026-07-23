//
//  ClearInteractionStateTask.swift
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

import Foundation

struct ClearInteractionStateTask: LaunchTask {

    let autoClearService: AutoClearServiceProtocol
    let interactionStateSource: TabInteractionStateSource?
    /// Not just this scene's own `TabManager`: the interaction-state cache directory is shared by
    /// every scene, so the exclusion set must be every currently-connected scene's tabs
    /// (`SceneRegistry.allConnectedTabs`), or a second window's cleanup task would delete a still-
    /// open first window's cached webview state (and vice versa).
    let sceneRegistry: SceneRegistry

    var name: String = "Clear Interaction State"

    func run(context: LaunchTaskContext) {
        guard !autoClearService.isTabClearingEnabled, let interactionStateSource else {
            context.finish()
            return
        }

        // Accessing tab models must happen on the main thread
        let statesToRemoveResult: Result<[URL], Error> = DispatchQueue.main.sync {
            interactionStateSource.urlsToRemove(excluding: sceneRegistry.allConnectedTabs)
        }

        // Perform file removal on the current background queue as it is thread-safe
        let statesToRemove: [URL]
        switch statesToRemoveResult {
        case .success(let urls):
            statesToRemove = urls
        case .failure:
            statesToRemove = []
        }
        _ = interactionStateSource.removeStates(at: statesToRemove, isCancelled: context.isCancelled)
        context.finish()
    }

}
