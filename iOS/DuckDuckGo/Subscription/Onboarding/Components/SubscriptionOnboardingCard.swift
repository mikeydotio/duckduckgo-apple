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
import UIComponents

/// The rounded card shell for the post-subscription onboarding flow: a design-system surface with an
/// optional `header`, its main `items` content, and an optional `footer`, stacked vertically. When a
/// header is present a full-width divider separates it from the content below. `bordered` adds a
/// hairline border; `borderless` is fill-only.
///
/// For a card built from `CardItem`s, use the `CardItem` / `[CardItem]` convenience initializers — the
/// list variants lay the rows out with a divider between adjacent rows (via `CardItemList`). For richer
/// layouts pass arbitrary views through the `header` / `items` / `footer` builders.
struct SubscriptionOnboardingCard<Header: View, Items: View, Footer: View>: View {
    /// The card's visual style.
    enum Style {
        case bordered
        case borderless
    }

    private let cornerRadius: CGFloat
    private let style: Style
    private let padding: CGFloat
    private let header: () -> Header
    private let items: () -> Items
    private let footer: () -> Footer

    init(cornerRadius: CGFloat = 26,
         style: Style = .bordered,
         padding: CGFloat = 16,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder items: @escaping () -> Items,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.padding = padding
        self.header = header
        self.items = items
        self.footer = footer
    }

    private var showsHeaderDivider: Bool {
        Header.self != EmptyView.self
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header()
            if showsHeaderDivider {
                fullWidthDivider
            }
            items()
            footer()
        }
        .padding(padding)
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

    /// A hairline that bleeds to the card's edges — the negative horizontal padding cancels the content
    /// padding, so it spans the full card width without widening the card.
    private var fullWidthDivider: some View {
        Color(designSystemColor: .lines)
            .frame(height: 1)
            .padding(.horizontal, -padding)
    }
}

extension SubscriptionOnboardingCard where Header == EmptyView, Items == CardItem {
    /// Creates a card holding a single `CardItem`, with no header or footer.
    init(_ item: CardItem,
         style: Style = .bordered,
         padding: CGFloat = 16) where Footer == EmptyView {
        self.init(style: style, padding: padding, header: { EmptyView() }, items: { item }, footer: { EmptyView() })
    }

    /// Creates a card holding a single `CardItem` with a footer below it.
    init(_ item: CardItem,
         style: Style = .bordered,
         padding: CGFloat = 16,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.init(style: style, padding: padding, header: { EmptyView() }, items: { item }, footer: footer)
    }
}

extension SubscriptionOnboardingCard where Items == CardItemList, Footer == EmptyView {
    /// Creates a card from an array of `CardItem`s (laid out as rows with a hairline divider between
    /// adjacent rows) with a `header` above them, separated by a full-width divider.
    ///
    /// - Parameters:
    ///   - items: The rows, top to bottom.
    ///   - dividerLeadingInset: How far each inter-row divider is inset from the leading edge so it
    ///     clears the icon column and starts under the text. Defaults to `36` (a 24pt icon plus its
    ///     12pt gutter); pass a larger value for larger icons, or `0` for a full-width divider.
    ///   - onSelect: Called with the tapped row's index; when `nil` the rows are not interactive.
    init(_ items: [CardItem],
         style: Style = .bordered,
         padding: CGFloat = 16,
         dividerLeadingInset: CGFloat = 36,
         onSelect: ((Int) -> Void)? = nil,
         @ViewBuilder header: @escaping () -> Header) {
        self.init(style: style, padding: padding, header: header, items: {
            CardItemList(items, dividerLeadingInset: dividerLeadingInset, onSelect: onSelect)
        }, footer: { EmptyView() })
    }

    /// Creates a card from an array of `CardItem`s (laid out as rows with a hairline divider between
    /// adjacent rows), with no header or footer. A single item (or none) draws no divider.
    ///
    /// - Parameters:
    ///   - items: The rows, top to bottom.
    ///   - dividerLeadingInset: How far each divider is inset from the leading edge so it clears the
    ///     icon column and starts under the text. Defaults to `36` (a 24pt icon plus its 12pt gutter);
    ///     pass a larger value for larger icons, or `0` for a full-width divider.
    ///   - onSelect: Called with the tapped row's index; when `nil` the rows are not interactive.
    init(_ items: [CardItem],
         style: Style = .bordered,
         padding: CGFloat = 16,
         dividerLeadingInset: CGFloat = 36,
         onSelect: ((Int) -> Void)? = nil) where Header == EmptyView {
        self.init(style: style, padding: padding, header: { EmptyView() }, items: {
            CardItemList(items, dividerLeadingInset: dividerLeadingInset, onSelect: onSelect)
        }, footer: { EmptyView() })
    }
}

/// Lays out a `[CardItem]` as a vertical list with a hairline divider between adjacent rows (a single
/// item, or none, draws no divider). Drop it into a `SubscriptionOnboardingCard`'s `items` slot — the
/// list convenience initializers do this for you; use it directly for other layouts.
struct CardItemList: View {
    private let items: [CardItem]
    private let dividerLeadingInset: CGFloat
    private let onSelect: ((Int) -> Void)?

    /// - Parameters:
    ///   - items: The rows, top to bottom.
    ///   - dividerLeadingInset: How far each divider is inset from the leading edge so it clears the
    ///     icon column and starts under the text. Defaults to `36` (a 24pt icon plus its 12pt gutter);
    ///     pass a larger value for larger icons, or `0` for a full-width divider.
    ///   - onSelect: Called with the tapped row's index; when `nil` the rows are not interactive.
    init(_ items: [CardItem], dividerLeadingInset: CGFloat = 36, onSelect: ((Int) -> Void)? = nil) {
        self.items = items
        self.dividerLeadingInset = dividerLeadingInset
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    Color(designSystemColor: .lines)
                        .frame(height: 1)
                        .padding(.leading, dividerLeadingInset)
                }
                row(entry.element, at: entry.offset)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: CardItem, at index: Int) -> some View {
        if let onSelect {
            Button {
                onSelect(index)
            } label: {
                item.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            item
        }
    }
}

#if DEBUG

import DuckUI

private struct SubscriptionOnboardingCardPreviewSamples: View {
    @State private var selection = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubscriptionOnboardingCard(
                    CardItem(
                        icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "creditcard.fill")), size: .size32),
                        title: "Recover financial losses",
                        titleFont: .footnoteSemibold,
                        text: "We'll work with financial institutions to help reverse fraudulent transactions."),
                    style: .bordered)

                SubscriptionOnboardingCard(
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "checkmark.seal.fill")), size: .size40),
                        title: "Setup 75% complete",
                        titleFont: .headline,
                        text: "Some premium protections aren't active yet",
                        textFont: .bodyRegular),
                    style: .borderless) {
                        Button("Continue Setup") {}
                            .buttonStyle(PrimaryButtonStyle())
                    }

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "checkmark.circle.fill")), size: .size24),
                        title: "DuckDuckGo VPN",
                        titleFont: .subheadRegular),
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "circle")), size: .size24),
                        title: "Personal Information Removal",
                        titleFont: .subheadRegular),
                ], style: .borderless) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "75%")
                            .font(.title.bold())
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        Capsule()
                            .fill(Color(designSystemColor: .accentPrimary))
                            .frame(height: 8)
                    }
                }

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "lock.shield.fill"))),
                        title: "VPN",
                        text: "An extra layer of online protection.",
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "person.text.rectangle.fill"))),
                        title: "Identity Theft Restoration",
                        text: "If your identity is stolen, we'll help restore it.",
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                    CardItem(
                        icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "sparkles"))),
                        title: "Advanced AI Models",
                        text: "Private conversations with 3rd-party AI chat models.",
                        trailing: .chevron(Color(designSystemColor: .iconsTertiary))),
                ], style: .borderless)

                SubscriptionOnboardingCard([
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "brain")), size: .size24),
                        title: "GPT-4o mini",
                        titleFont: .bodyRegular,
                        trailing: selection == 0 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                    CardItem(
                        icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "cpu")), size: .size24),
                        title: "Claude",
                        titleFont: .bodyRegular,
                        titleDetails: [.init(text: "· PLUS", font: .footnoteRegular)],
                        trailing: selection == 1 ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil),
                ], style: .borderless, onSelect: { selection = $0 })
            }
            .padding()
        }
        .background(Color(designSystemColor: .background).ignoresSafeArea())
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
