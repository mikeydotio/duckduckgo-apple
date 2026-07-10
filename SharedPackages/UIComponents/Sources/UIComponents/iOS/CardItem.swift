//
//  CardItem.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

/// The design-system size for a ``CardItem``'s icon.
public enum CardItemIconSize {
    case size24
    case size32
    case size40
    case size56

    var points: CGFloat {
        switch self {
        case .size24: 24
        case .size32: 32
        case .size40: 40
        case .size56: 56
        }
    }
}

/// An icon shown by a ``CardItem``, together with where it sits relative to the text.
public struct CardItemIcon {
    /// The icon's position relative to the card item's text block.
    public enum Position: Equatable {
        /// In a leading column, aligned to the top of the content.
        case leading
        /// Above the text block.
        case topLeading
        /// In a leading column, vertically centered with the content.
        case leadingColumn
    }

    public let position: Position
    public let visual: CardVisual
    public let size: CardItemIconSize
    /// The gap between a leading icon and the text block. Ignored for `.topLeading`.
    public let spacing: CGFloat

    public init(position: Position, visual: CardVisual, size: CardItemIconSize = .size24, spacing: CGFloat = 8) {
        self.position = position
        self.visual = visual
        self.size = size
        self.spacing = spacing
    }
}

/// A trailing accessory shown at the end of a ``CardItem``. The colour is supplied by the caller so
/// the surrounding screen controls the tint.
public enum CardItemAccessory {
    case chevron(Color)
    case checkmark(Color)
}

/// A design-system font token for a ``CardItem``. Each value maps to a DesignResourcesKit dax font;
/// the private initializer keeps callers on this curated set rather than arbitrary fonts.
public struct CardItemFont {
    let font: Font

    private init(_ font: Font) {
        self.font = font
    }
}

public extension CardItemFont {
    static let headline = CardItemFont(Font(UIFont.daxHeadline()))
    static let bodyRegular = CardItemFont(Font(UIFont.daxBodyRegular()))
    static let subheadRegular = CardItemFont(Font(UIFont.daxSubheadRegular()))
    static let footnoteRegular = CardItemFont(Font(UIFont.daxFootnoteRegular()))
    static let footnoteSemibold = CardItemFont(Font(UIFont.daxFootnoteSemibold()))
}

/// An inline detail shown after the title — for example a variant name or a tier marker. Each
/// carries its own ``CardItemFont`` and renders in the secondary text colour.
public struct CardItemTitleDetail {
    public let text: String
    public let font: CardItemFont

    public init(text: String, font: CardItemFont) {
        self.text = text
        self.font = font
    }
}

/// A single card content row: an optional icon, an optional overline, a title with optional inline
/// details (e.g. a variant name or tier marker), optional body text, and an optional trailing accessory.
/// An optional `accessibilityValue` merges the row into a single VoiceOver element carrying that value
/// (e.g. a "Selected" or "Completed" state).
///
/// `CardItem` lays out content only; the surrounding surface is supplied by the card shell that holds it
public struct CardItem: View {
    private let icon: CardItemIcon?
    private let overline: String?
    private let title: String?
    private let titleFont: CardItemFont
    private let titleDetails: [CardItemTitleDetail]
    private let text: String?
    private let textFont: CardItemFont
    /// The vertical gap between the title and the body text.
    private let titleTextSpacing: CGFloat
    private let trailing: CardItemAccessory?
    private let accessibilityValue: String?
    private let minHeight: CGFloat?

    public init(icon: CardItemIcon? = nil,
                overline: String? = nil,
                title: String? = nil,
                titleFont: CardItemFont = .headline,
                titleDetails: [CardItemTitleDetail] = [],
                text: String? = nil,
                textFont: CardItemFont = .footnoteRegular,
                titleTextSpacing: CGFloat = 4,
                trailing: CardItemAccessory? = nil,
                accessibilityValue: String? = nil,
                minHeight: CGFloat? = nil) {
        self.icon = icon
        self.overline = overline
        self.title = title
        self.titleFont = titleFont
        self.titleDetails = titleDetails
        self.text = text
        self.textFont = textFont
        self.titleTextSpacing = titleTextSpacing
        self.trailing = trailing
        self.accessibilityValue = accessibilityValue
        self.minHeight = minHeight
    }

    @ViewBuilder
    public var body: some View {
        if let minHeight {
            rowContent.frame(minHeight: minHeight, alignment: .topLeading)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: rowAlignment, spacing: 0) {
                if let icon, icon.position == .leading || icon.position == .leadingColumn {
                    iconVisual(icon)
                        .padding(.trailing, icon.spacing)
                }

                textBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                trailingIcon(for: trailing)
                    .padding(.leading, 8)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .combinedAccessibilityValue(accessibilityValue)
    }

    private var rowAlignment: VerticalAlignment {
        icon?.position == .leading ? .top : .center
    }

    @ViewBuilder
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let icon, icon.position == .topLeading {
                iconVisual(icon)
            }
            if let overline {
                Text(verbatim: overline)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            VStack(alignment: .leading, spacing: titleTextSpacing) {
                titleLine
                if let text {
                    Text(verbatim: text)
                        .font(textFont.font)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if title != nil || !titleDetails.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let title {
                    Text(verbatim: title)
                        .font(titleFont.font)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
                ForEach(Array(titleDetails.enumerated()), id: \.offset) { _, detail in
                    Text(verbatim: detail.text)
                        .font(detail.font.font)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
            }
        }
    }

    private func iconVisual(_ icon: CardItemIcon) -> some View {
        CardVisualView(visual: icon.visual, size: icon.size.points)
    }

    @ViewBuilder
    private func trailingIcon(for accessory: CardItemAccessory) -> some View {
        switch accessory {
        case .chevron(let color):
            Image(systemName: "chevron.forward")
                .foregroundColor(color)
        case .checkmark(let color):
            Image(systemName: "checkmark")
                .foregroundColor(color)
        }
    }
}

private extension View {
    /// Merges the row into one accessibility element carrying `value` (e.g. "Selected", "Completed"),
    /// or leaves the view unchanged when `value` is `nil`.
    @ViewBuilder
    func combinedAccessibilityValue(_ value: String?) -> some View {
        if let value {
            accessibilityElement(children: .combine)
                .accessibilityValue(value)
        } else {
            self
        }
    }
}

#if DEBUG

private struct CardItemPreviewSamples: View {
    var body: some View {
        VStack(spacing: 16) {
            CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "sparkles")), size: .size24),
                title: "Claude",
                titleFont: .bodyRegular,
                titleDetails: [.init(text: "Sonnet 4.6", font: .bodyRegular), .init(text: "· PLUS", font: .footnoteRegular)],
                text: "Uses limits faster",
                trailing: .checkmark(Color(designSystemColor: .accentPrimary)))

            CardItem(
                icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "dollarsign.circle.fill")), size: .size56),
                title: "Recover financial losses",
                titleFont: .headline,
                text: """
                    We'll work with financial institutions to help reverse any fraudulent \
                    transactions, and we'll reimburse certain out-of-pocket expenses*** in the \
                    event that you become a victim of identity theft or fraud.
                    """,
                textFont: .subheadRegular)

            CardItem(
                icon: CardItemIcon(position: .leading, visual: .image(Image(systemName: "lock.shield.fill")), size: .size24),
                title: "VPN",
                titleFont: .bodyRegular,
                text: "Get an extra layer of online protection with the VPN built for speed and simplicity.",
                trailing: .chevron(Color(designSystemColor: .iconsTertiary)))
        }
        .padding()
    }
}

private struct CardItemSparseSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "lock.shield.fill"))),
                    title: "DuckDuckGo VPN",
                    titleFont: .bodyRegular)

                CardItem(title: "Open settings", trailing: .chevron(Color(designSystemColor: .iconsTertiary)))

                CardItem(
                    icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "person.fill"))),
                    title: "Account",
                    text: "Manage your account",
                    trailing: .chevron(Color(designSystemColor: .iconsTertiary)))

                CardItem(title: "Advanced Models", titleDetails: [.init(text: "· PLUS", font: .footnoteRegular)])

                CardItem(title: "Title only")
            }
            .background(Color(designSystemColor: .surface))

            Group {
                CardItem(text: "Body text only — no icon, no title.")

                CardItem(icon: CardItemIcon(position: .leadingColumn, visual: .image(Image(systemName: "star.fill"))))

                CardItem(
                    icon: CardItemIcon(position: .topLeading, visual: .image(Image(systemName: "star.fill"))),
                    title: "Top-leading icon, no body")

                CardItem(overline: "OVERLINE", title: "Overline + title")

                CardItem()
            }
            .background(Color(designSystemColor: .surface))
        }
        .padding()
    }
}

#Preview("Light") {
    CardItemPreviewSamples()
}

#Preview("Dark") {
    CardItemPreviewSamples()
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    CardItemPreviewSamples()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Sparse fields") {
    CardItemSparseSamples()
}

#endif

#endif
