//
//  ColorView.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Cocoa

internal class ColorView: DraggingDestinationView {

    private let fillLayer = CALayer()

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setupView()
    }

    init(frame: NSRect, backgroundColor: NSColor? = nil, cornerRadius: CGFloat = 0, roundedCorners: RoundedCorners = .all, borderColor: NSColor? = nil, borderWidth: CGFloat = 0, interceptClickEvents: Bool = false) {
        super.init(frame: frame)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.roundedCorners = roundedCorners
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.interceptClickEvents = interceptClickEvents

        setupView()
    }

    /// When `true` colors will be reserved against the `effectiveAppearance` value.
    /// Otherwise, we'll rely on `NSApp.effectiveAppearance`
    var resolvesStyleWithEffectiveAppearance: Bool = false {
        didSet {
            guard resolvesStyleWithEffectiveAppearance != oldValue else {
                return
            }

            updateLayerColors()
        }
    }

    private var targetAppearance: NSAppearance? {
        resolvesStyleWithEffectiveAppearance ? effectiveAppearance : nil
    }

    @IBInspectable var backgroundColor: NSColor? = NSColor.clear {
        didSet {
            updateLayerColors()
        }
    }

    @IBInspectable var cornerRadius: CGFloat = 0 {
        didSet {
            updateCornerRadius()
        }
    }

    var roundedCorners: RoundedCorners = .all {
        didSet {
            updateCornerRadius()
        }
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = cornerRadius
        layer?.maskedCorners = roundedCorners.cornerMask
        layer?.masksToBounds = true
        layoutFillLayer()
    }

    @IBInspectable var borderColor: NSColor? {
        didSet {
            updateLayerColors()
        }
    }

    @IBInspectable var borderWidth: CGFloat = 0 {
        didSet {
            updateBorderWidth()
        }
    }
    private func updateBorderWidth() {
        layer?.borderWidth = borderWidth
    }

    @IBInspectable var interceptClickEvents: Bool = false

    func setupView() {
        self.wantsLayer = true

        setupFillLayer()
        updateLayerColors()
        updateCornerRadius()
        updateBorderWidth()
    }

    override func updateLayer() {
        super.updateLayer()
        updateLayerColors()
    }

    override func layout() {
        super.layout()
        layoutFillLayer()
    }

    private func updateLayerColors() {
        NSAppearance.withAppearance(targetAppearance) {
            fillLayer.backgroundColor = backgroundColor?.cgColor
            layer?.borderColor = borderColor?.cgColor
        }
    }

    private func layoutFillLayer() {
        fillLayer.frame = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        fillLayer.cornerRadius = max(0, cornerRadius - borderWidth)
        fillLayer.maskedCorners = roundedCorners.cornerMask
    }

    private func setupFillLayer() {
        fillLayer.zPosition = -1
        fillLayer.actions = [
            "backgroundColor": NSNull(),
            "cornerRadius": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
        layer?.addSublayer(fillLayer)
    }

    // MARK: - Click Event Interception

    override func mouseDown(with event: NSEvent) {
        if !interceptClickEvents {
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !interceptClickEvents {
            super.mouseUp(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !interceptClickEvents {
            super.mouseDragged(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if !interceptClickEvents {
            super.rightMouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if !interceptClickEvents {
            super.otherMouseDown(with: event)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        fillLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
}

struct RoundedCorners: OptionSet {
    let rawValue: Int

    static let topLeft = RoundedCorners(rawValue: 1 << 0)
    static let topRight = RoundedCorners(rawValue: 1 << 1)
    static let bottomLeft = RoundedCorners(rawValue: 1 << 2)
    static let bottomRight = RoundedCorners(rawValue: 1 << 3)

    static let all: RoundedCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var cornerMask: CACornerMask {
        var mask: CACornerMask = []
        if contains(.topLeft) {
            mask.insert(.layerMinXMaxYCorner)
        }

        if contains(.topRight) {
            mask.insert(.layerMaxXMaxYCorner)
        }

        if contains(.bottomLeft) {
            mask.insert(.layerMinXMinYCorner)
        }

        if contains(.bottomRight) {
            mask.insert(.layerMaxXMinYCorner)
        }

        return mask
    }
}
