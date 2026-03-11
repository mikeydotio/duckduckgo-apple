//
//  Terminating.swift
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
import Foundation

@MainActor
struct Terminating: TerminatingHandling {

    let error: Error?

    init(error: Error) {
        self.error = error
        Logger.general.error("App entering terminating state due to error: \(error.localizedDescription)")
    }

    init() {
        self.error = nil
    }

    func terminate() {
        guard let error else { return }
        // Fatal error during launch — log and crash.
        // Phase 2: may show alert to user before terminating.
        Logger.general.fault("Fatal error during launch, terminating: \(error.localizedDescription)")
        Thread.sleep(forTimeInterval: 1)
        fatalError("Fatal error during launch: \(error.localizedDescription)")
    }

}
