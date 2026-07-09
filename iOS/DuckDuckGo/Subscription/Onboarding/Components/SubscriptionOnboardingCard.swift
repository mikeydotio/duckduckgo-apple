//
//  SubscriptionOnboardingCard.swift
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

/// The rounded card shell for the post-subscription onboarding flow: a design-system surface that
/// holds one or more `CardItem`s and an optional footer (a grid, a button, and so on). `bordered`
/// adds a hairline border; `borderless` is fill-only.
struct SubscriptionOnboardingCard<Items: View, Footer: View>: View {
    /// The card's visual style.
    enum Style {
        case bordered
        case borderless
    }

    private let cornerRadius: CGFloat
    private let style: Style
    private let items: () -> Items
    private let footer: () -> Footer

    init(cornerRadius: CGFloat = 26,
         style: Style = .bordered,
         @ViewBuilder items: @escaping () -> Items,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.items = items
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            items()
            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(designSystemColor: .surfaceSecondary))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if style == .bordered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(designSystemColor: .lines), lineWidth: 1)
            }
        }
    }
}

extension SubscriptionOnboardingCard where Footer == EmptyView {
    /// Creates a card with no footer.
    init(style: Style = .bordered, @ViewBuilder items: @escaping () -> Items) {
        self.init(style: style, items: items, footer: { EmptyView() })
    }
}

#if DEBUG

import UIComponents
import DesignResourcesKitIcons
import DuckUI

private struct SubscriptionOnboardingCardPreviewSamples: View {
    var body: some View {
        ZStack {
            Color(designSystemColor: .background).ignoresSafeArea()
            VStack(spacing: 24) {
                SubscriptionOnboardingCard(style: .bordered) {
                    CardItem(
                        icon: CardItemIcon(
                            position: .topLeading,
                            visual: .image(Image(uiImage: DesignSystemImages.Color.Size24.creditCardCheck)),
                            size: .size32),
                        title: "Recover financial losses",
                        titleFont: .footnoteSemibold,
                        text: """
                            We'll work with financial institutions to help reverse any fraudulent \
                            transactions, and we'll reimburse certain out-of-pocket expenses*** in \
                            the event that you become a victim of identity theft or fraud.
                            """)
                }

                SubscriptionOnboardingCard(style: .borderless) {
                    CardItem(
                        icon: CardItemIcon(
                            position: .leading,
                            visual: .image(Image(uiImage: DesignSystemImages.Color.Size24.subscription)),
                            size: .size40),
                        title: "Setup 75% complete",
                        titleFont: .headline,
                        text: "Some premium protections aren't active yet",
                        textFont: .bodyRegular)
                } footer: {
                    Button("Continue Setup") {}
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding()
        }
    }
}

private struct RebrandedPreview<Content: View>: View {
    @StateObject private var rebrandOverride = RebrandPreviewOverride(isRebranded: true)
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onAppear { rebrandOverride.apply() }
    }
}

#Preview("Rebranded / Light") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
}

#Preview("Rebranded / Dark") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
    .preferredColorScheme(.dark)
}

#Preview("Rebranded / Large Text") {
    RebrandedPreview {
        SubscriptionOnboardingCardPreviewSamples()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
