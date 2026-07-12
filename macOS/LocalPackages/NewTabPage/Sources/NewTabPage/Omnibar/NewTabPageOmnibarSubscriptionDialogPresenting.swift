//
//  NewTabPageOmnibarSubscriptionDialogPresenting.swift
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

/// Presents native subscription dialogs on behalf of the NTP omnibar, in response to
/// `omnibar_showSubscriptionUpsell`/`omnibar_showSubscriptionUpgrade`. Which flow to run is
/// determined entirely by which method is called — both messages are param-less, since the web
/// side already knows (from a gated model/reasoning-effort's own `upsell` field) whether the user
/// needs to subscribe or upgrade.
@MainActor
public protocol NewTabPageOmnibarSubscriptionDialogPresenting {
    func showSubscriptionUpsellDialog()
    func showSubscriptionUpgradeDialog()
}
