//
//  EscapeHatchActions.swift
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

/// Bundles the four user-driven actions exposed by the escape-hatch UI so they thread through
/// the editing-state / NTP / AI-chat stacks as a single value instead of four parallel closures.
struct EscapeHatchActions {
    let onCardTap: () -> Void
    let onTabSwitcherTap: () -> Void
    let onCloseTab: () -> Void
    let onBurnTab: () -> Void
}

/// Single sink for the four escape-hatch verbs. Implemented by the object that actually fulfils the
/// actions (today: `MainViewController`). View controllers that need to construct an `EscapeHatchActions`
/// hold a weak reference to this and use `EscapeHatchActions(router:targetTab:)` instead of bundling
/// closures by hand.
protocol EscapeHatchActionRouter: AnyObject {
    func escapeHatchDidRequestSwitch(to tab: Tab)
    func escapeHatchDidRequestClose(_ tab: Tab)
    func escapeHatchDidRequestBurn(_ tab: Tab)
    func escapeHatchDidRequestTabSwitcher()
}

extension EscapeHatchActions {
    /// Builds the four-closure bundle from a router + target tab. The router is captured weakly so
    /// holders of `EscapeHatchActions` don't pin their owner's lifecycle.
    init(router: EscapeHatchActionRouter, targetTab: Tab) {
        self.init(
            onCardTap: { [weak router] in router?.escapeHatchDidRequestSwitch(to: targetTab) },
            onTabSwitcherTap: { [weak router] in router?.escapeHatchDidRequestTabSwitcher() },
            onCloseTab: { [weak router] in router?.escapeHatchDidRequestClose(targetTab) },
            onBurnTab: { [weak router] in router?.escapeHatchDidRequestBurn(targetTab) }
        )
    }
}
