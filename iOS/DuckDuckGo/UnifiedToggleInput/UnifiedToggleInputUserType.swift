//
//  UnifiedToggleInputUserType.swift
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
import SetDefaultBrowserCore

/// Minimal user-type signal the Unified Toggle Input gate needs: is this device a brand-new install?
///
/// Owned by UTI so the gate doesn't depend on the Default Browser Prompt classifier's enum directly.
/// `isNewUser` is intentionally narrow — only `.new` installs are "new"; returning, existing and an
/// undetermined classification all read as `false` (eligible / fail open).
protocol UnifiedToggleInputUserTypeProviding {
    var isNewUser: Bool { get }
}

/// Adapts the snapshotted Default Browser Prompt classifier to the UTI gate's `isNewUser` signal.
/// Reuses the existing per-device snapshot — it does not compute or persist a new one.
struct DefaultBrowserPromptUnifiedToggleInputUserTypeAdapter: UnifiedToggleInputUserTypeProviding {

    private let userTypeProvider: DefaultBrowserPromptUserTypeProviding

    init(userTypeProvider: DefaultBrowserPromptUserTypeProviding) {
        self.userTypeProvider = userTypeProvider
    }

    var isNewUser: Bool {
        userTypeProvider.currentUserType() == .new
    }
}
