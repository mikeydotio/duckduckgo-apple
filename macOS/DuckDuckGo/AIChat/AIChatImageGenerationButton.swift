//
//  AIChatImageGenerationButton.swift
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
import DesignResourcesKitIcons

/// A pill-shaped toggle button for activating image generation mode in the AI Chat omnibar.
/// Displays an icon and "Create Image" label. When toggled on, shows an accent background.
final class AIChatImageGenerationButton: NSView {

    private enum Constants {
        static let height: CGFloat = 28
        static let horizontalPadding: CGFloat = 10
        static let iconTextSpacing: CGFloat = 4
        static let iconSize: CGFloat = 16
        static let fontSize: CGFloat = 12
        static let cornerRadius: CGFloat = 14
    }

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size16.wand
        return imageView
    }()

    private let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.fontSize, weight: .regular)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let backgroundLayer = CALayer()

    var onToggled: ((Bool) -> Void)?
    var onTabPressed: (() -> Void)?

    var title: String = "" {
        didSet {
            nameLabel.stringValue = title
            invalidateIntrinsicContentSize()
        }
    }

    var tintColor: NSColor? {
        didSet {
            updateAppearance()
        }
    }

    var hoverBackgroundColor: NSColor = .clear
    var pressedBackgroundColor: NSColor = .clear
    var toggledBackgroundColor: NSColor = .clear
    var toggledTintColor: NSColor = .white

    var isToggled: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    private var isHovered = false {
        didSet {
            updateAppearance()
        }
    }

    private var isMouseDown = false {
        didSet {
            updateAppearance()
        }
    }

    override var intrinsicContentSize: NSSize {
        let labelWidth = nameLabel.intrinsicContentSize.width
        let totalWidth = Constants.horizontalPadding + Constants.iconSize + Constants.iconTextSpacing + labelWidth + Constants.horizontalPadding
        return NSSize(width: totalWidth, height: Constants.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        setNeedsDisplay(bounds.insetBy(dx: -3, dy: -3))
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        setNeedsDisplay(bounds.insetBy(dx: -3, dy: -3))
        return super.resignFirstResponder()
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityRole(.button)

        backgroundLayer.cornerRadius = Constants.cornerRadius
        backgroundLayer.opacity = 0
        layer?.insertSublayer(backgroundLayer, at: 0)

        addSubview(iconImageView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: Constants.iconTextSpacing),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
        setupHoverTracking()
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        NSAppearance.withAppAppearance {
            if isToggled {
                backgroundLayer.backgroundColor = toggledBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                nameLabel.textColor = toggledTintColor
                iconImageView.contentTintColor = toggledTintColor
            } else if isMouseDown {
                backgroundLayer.backgroundColor = pressedBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                nameLabel.textColor = tintColor
                iconImageView.contentTintColor = tintColor
            } else if isHovered {
                backgroundLayer.backgroundColor = hoverBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                nameLabel.textColor = tintColor
                iconImageView.contentTintColor = tintColor
            } else {
                backgroundLayer.opacity = 0
                nameLabel.textColor = tintColor
                iconImageView.contentTintColor = tintColor
            }
        }

        CATransaction.commit()
    }

    // MARK: - Hover Tracking

    private var trackingArea: NSTrackingArea?

    private func setupHoverTracking() {
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
    }

    override func mouseDragged(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        isMouseDown = bounds.contains(locationInView)
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) && isMouseDown {
            isToggled.toggle()
            onToggled?(isToggled)
        }
        isMouseDown = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder == self else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.resetClip()

        NSColor.controlAccentColor.setStroke()
        let borderRect = bounds.insetBy(dx: -1, dy: -1)
        let focusPath = NSBezierPath(roundedRect: borderRect, xRadius: borderRect.height / 2, yRadius: borderRect.height / 2)
        focusPath.lineWidth = 1.5
        focusPath.lineCapStyle = .round
        focusPath.lineJoinStyle = .round
        focusPath.stroke()

        context.restoreGState()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: // Tab
            if let onTabPressed {
                onTabPressed()
            } else {
                super.keyDown(with: event)
            }
        case 49, 36: // Space, Return - toggle
            isToggled.toggle()
            onToggled?(isToggled)
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
