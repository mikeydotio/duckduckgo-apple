//
//  AIChatViewAllChatsRowView.swift
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

import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// A footer row displayed at the bottom of the address bar suggestions panel.
/// Shows "View all chats" on the left and "Open Duck.ai →" on the right with keyboard shortcut badges.
/// Tapping it opens Duck.ai.
final class AIChatViewAllChatsRowView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconTitleSpacing: CGFloat = 6
        static let cornerRadius: CGFloat = 6
        static let trailingSpacing: CGFloat = 4
        static let iconColor: NSColor = .suggestionIcon
        static let textColor: NSColor = NSColor(designSystemColor: .textPrimary)
        static let selectedTintColor: NSColor = .selectedSuggestionTint
    }

    // MARK: - UI Components

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.history
        imageView.contentTintColor = Constants.iconColor
        return imageView
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatViewAllChatsTitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }()

    private let shortcutView: KeyboardShortcutView = {
        let view = KeyboardShortcutView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: ["⌥", "↩"])
        return view
    }()

    private let trailingLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatViewAllChatsOpenDuckAI)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }()

    private let backgroundLayer = CALayer()

    // MARK: - Properties

    private var trackingArea: NSTrackingArea?

    var isHovered: Bool = false {
        didSet { updateAppearance() }
    }

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var onClick: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        backgroundLayer.cornerRadius = Constants.cornerRadius
        layer?.insertSublayer(backgroundLayer, at: 0)

        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(shortcutView)
        addSubview(trailingLabel)

        // Set accent color for trailing label — mirrors the search panel's "Ask privately →" styling
        NSAppearance.withAppAppearance {
            trailingLabel.textColor = NSApp.delegateTyped.themeManager.theme.palette.accentPrimary
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.rowHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTitleSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            shortcutView.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -Constants.trailingSpacing),
            shortcutView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    // MARK: - Appearance

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let highlighted = isSelected || isHovered
        shortcutView.isHighlighted = highlighted

        if highlighted {
            NSAppearance.withAppAppearance {
                backgroundLayer.backgroundColor = NSApp.delegateTyped.themeManager.theme.palette.accentPrimary.cgColor
            }
            titleLabel.textColor = Constants.selectedTintColor
            trailingLabel.textColor = Constants.selectedTintColor
            iconImageView.contentTintColor = Constants.selectedTintColor
        } else {
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = Constants.textColor
            NSAppearance.withAppAppearance {
                trailingLabel.textColor = NSApp.delegateTyped.themeManager.theme.palette.accentPrimary
                iconImageView.contentTintColor = Constants.iconColor
            }
        }

        CATransaction.commit()
    }

    // MARK: - Appearance Updates

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if !(isSelected || isHovered) {
            NSAppearance.withAppAppearance {
                trailingLabel.textColor = NSApp.delegateTyped.themeManager.theme.palette.accentPrimary
            }
        }
        updateAppearance()
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHoverChanged?(true)
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isSelected = true
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) {
            onClick?()
        }
        isSelected = false
    }
}
