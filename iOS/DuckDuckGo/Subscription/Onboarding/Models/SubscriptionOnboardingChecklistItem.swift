//
//  SubscriptionOnboardingChecklistItem.swift
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

/// The fixed set of protections tracked on the completion checklist. Each case owns its display title;
/// `.pir` (Personal Information Removal) is the one that can remain incomplete in the flow, so the
/// progress view treats it specially (blocked-profile icon, chevron, tappable).
enum SubscriptionOnboardingChecklistItem: CaseIterable {
    case vpn
    case idtr
    case duckAI
    case pir

    var title: String {
        switch self {
        case .vpn: return UserText.subscriptionOnboardingChecklistVPNTitle
        case .idtr: return UserText.subscriptionOnboardingChecklistIDTRTitle
        case .duckAI: return UserText.subscriptionOnboardingChecklistDuckAITitle
        case .pir: return UserText.subscriptionOnboardingChecklistPIRTitle
        }
    }
}
