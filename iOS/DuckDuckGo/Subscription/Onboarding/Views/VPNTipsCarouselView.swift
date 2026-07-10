//
//  VPNTipsCarouselView.swift
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
import UIComponents

/// The "What to know about using your VPN" carousel: three horizontally-scrolling cards, each an icon +
/// headline + body. Cards are a fixed width with the neighbours peeking at the edges; the row scrolls
/// freely (no paging/snapping — iOS 17's snap APIs are unavailable at the 15.0 floor). Each card reuses
/// `SubscriptionOnboardingCard` + `CardItem` for its surface and content.
struct VPNTipsCarouselView: View {
    private enum Metrics {
        static let cardWidth: CGFloat = 217
        static let cardHeight: CGFloat = 346
        static let cardPadding: CGFloat = 24
        static let cardSpacing: CGFloat = 16
        static let horizontalInset: CGFloat = 24
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Metrics.cardSpacing) {
                ForEach(Tip.allCases, id: \.self) { tip in
                    card(for: tip)
                }
            }
            .padding(.horizontal, Metrics.horizontalInset)
        }
    }

    private func card(for tip: Tip) -> some View {
        SubscriptionOnboardingCard(
            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: .image(tip.icon), size: .size56),
                title: tip.title,
                titleFont: .headline,
                text: tip.bodyText,
                textFont: .subheadRegular,
                minHeight: Metrics.cardHeight - Metrics.cardPadding * 2),
            style: .borderless,
            padding: Metrics.cardPadding)
        .frame(width: Metrics.cardWidth)
        .accessibilityElement(children: .combine)
    }

    private enum Tip: CaseIterable {
        case noCaps
        case speed
        case blocked

        var icon: Image {
            switch self {
            case .noCaps: Image("Keyhole-56")
            case .speed: Image("Response-Good-56")
            case .blocked: Image("VPN-56")
            }
        }

        var title: String {
            switch self {
            case .noCaps: UserText.subscriptionOnboardingVPNTipNoCapsTitle
            case .speed: UserText.subscriptionOnboardingVPNTipSpeedTitle
            case .blocked: UserText.subscriptionOnboardingVPNTipBlockedTitle
            }
        }

        var bodyText: String {
            switch self {
            case .noCaps: UserText.subscriptionOnboardingVPNTipNoCapsBody
            case .speed: UserText.subscriptionOnboardingVPNTipSpeedBody
            case .blocked: UserText.subscriptionOnboardingVPNTipBlockedBody
            }
        }
    }
}

#if DEBUG

private struct VPNTipsCarouselViewPreview: View {
    var body: some View {
        VStack {
            Spacer()
            VPNTipsCarouselView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(designSystemColor: .background).ignoresSafeArea())
    }
}

#Preview("Light") {
    RebrandedPreview {
        VPNTipsCarouselViewPreview()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        VPNTipsCarouselViewPreview()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        VPNTipsCarouselViewPreview()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
