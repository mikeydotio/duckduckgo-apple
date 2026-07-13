//
//  SubscriptionOnboardingVPNInfoCard.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

/// An IP-address info card for the post-subscription onboarding VPN step: a leading icon beside a labelled
/// IP address and its geolocation. The `state` selects the overline label and icon — the grayscale VPN icon
/// for the customer's real IP (`visibleIP` / `hiddenIP`) and the colour VPN icon for the new egress IP
/// (`newIP`) — while `ipAddress` and `location` carry the runtime values. Built from
/// `SubscriptionOnboardingCard` + a single `CardItem`.
struct SubscriptionOnboardingVPNInfoCard: View {

    /// Which IP the card describes; drives the overline label and the leading icon.
    enum State {
        case visibleIP
        case hiddenIP
        case newIP
    }

    private let state: State
    private let ipAddress: String
    private let location: String

    init(state: State, ipAddress: String, location: String) {
        self.state = state
        self.ipAddress = ipAddress
        self.location = location
    }

    var body: some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(state.icon), size: .size24, spacing: 8),
                overline: CardItemText(state.overline, font: .footnoteRegular),
                title: CardItemText(ipAddress, font: .bodyRegular),
                text: CardItemText(location, font: .footnoteRegular)),
            style: .borderless,
            contentInset: CardItemList.ContentInset(horizontal: 16, vertical: 14))
        .accessibilityElement(children: .combine)
    }
}

private extension SubscriptionOnboardingVPNInfoCard.State {
    var overline: String {
        switch self {
        case .visibleIP: UserText.subscriptionOnboardingVPNInfoVisibleIP
        case .hiddenIP: UserText.subscriptionOnboardingVPNInfoHiddenIP
        case .newIP: UserText.subscriptionOnboardingVPNInfoNewIP
        }
    }

    var icon: Image {
        switch self {
        case .visibleIP, .hiddenIP: Image("VPN-Grayscale-Color-24")
        case .newIP: Image(uiImage: DesignSystemImages.Color.Size24.vpn)
        }
    }
}

#if DEBUG

private struct SubscriptionOnboardingVPNInfoCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SubscriptionOnboardingVPNInfoCard(state: .visibleIP, ipAddress: "31.120.130.50", location: "🇪🇸 Madrid, Spain")
                SubscriptionOnboardingVPNInfoCard(state: .hiddenIP, ipAddress: "31.120.130.50", location: "🇪🇸 Madrid, Spain")
                SubscriptionOnboardingVPNInfoCard(state: .newIP, ipAddress: "45.623.728.96", location: "🇪🇸 Valencia, Spain (Nearest)")
            }
            .padding()
        }
        .background(Color(designSystemColor: .background).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingVPNInfoCardPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
