//
//  Foreground.swift
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

import AppKit

@MainActor
struct Foreground: ForegroundHandling {

    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func onTransition() {
        // Phase 1: AppDelegate.applicationDidBecomeActive still runs its own logic.
        // In Phase 2, that logic moves here.
    }

    func didReturn() {
        // Called on subsequent didBecomeActive while already in foreground.
        // Phase 1: no-op (AppDelegate handles this via its didFinishLaunching guard).
    }

    func handleTerminationRequest() -> NSApplication.TerminateReply {
        // Phase 1: always approve termination.
        // Phase 3: delegate to TerminationDeciderHandler chain.
        return .terminateNow
    }

}
