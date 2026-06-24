//
//  TabsBarCell.swift
//  DuckDuckGo
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

import UIKit
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

class TabsBarCell: UICollectionViewCell {

    /// Geometry of the selected ("current") tab's flared / connected shape.
    ///
    /// The selected tab is drawn as a custom shape (`SelectedTabShape` / `selectedBackgroundLayer`)
    /// with convex rounded TOP corners and OUTWARD-flaring concave BOTTOM corners that merge into the
    /// omni bar directly below — the macOS Safari/Chrome active-tab look.
    ///
    /// Values are derived from the design mock's @2x annotations (divide by 2 for points). Tune here;
    /// this is the single source of truth for the shape.
    enum Metrics {
        /// Radius of the convex TOP corners. The mock's omni bar / active tab read ~24–32 @2x at the
        /// top; the storyboard's legacy `topBackgroundView` used 12pt, which also matches the omni
        /// bar pill's leading curve, so we keep 12pt for visual continuity. (~24 @2x)
        static let topCornerRadius: CGFloat = 12

        /// Radius of the OUTWARD-flaring concave BOTTOM corners. Derived from the mock's "24" @2x
        /// horizontal bracket between the window controls and the tab's leading flare → 12pt. This is
        /// both the concave arc radius and how far each flare extends horizontally past the tab body.
        static let bottomFlareRadius: CGFloat = 12

        /// How far the shape's very bottom edge drops below the cell's bottom, so the flare overlaps
        /// the omni bar's top edge and the two surfaces merge with no seam. From the mock's lower
        /// "9" @2x → ~4.5pt; rounded to 4pt. Keep ≥ 0 and small.
        static let bottomOverlap: CGFloat = 4

        /// zPosition applied to the selected cell so its outward flares (which extend into the
        /// inter-tab spacing) render ABOVE neighbouring cells instead of being clipped by them.
        static let selectedCellZPosition: CGFloat = 1
    }

    @IBOutlet weak var label: FadeOutLabel!
    @IBOutlet weak var removeButton: BrowserChromeButton!
    @IBOutlet weak var faviconImage: UIImageView!
    @IBOutlet weak var topBackgroundView: UIView!
    @IBOutlet weak var bottomBackgroundView: UIView!
    @IBOutlet weak var separatorView: UIView!
    @IBOutlet var labelRemoveButtonConstraint: NSLayoutConstraint!

    var isPressed = false {
        didSet {
            setNeedsLayout()
        }
    }

    var onRemove: (() -> Void)?

    private weak var model: Tab?
    private var isFireModeEnabled = false

    /// Backs the selected tab's flared shape. Inserted below the cell's content so the favicon,
    /// label and close button draw on top. `nil`/empty path when the cell is not current.
    private let selectedBackgroundLayer = CAShapeLayer()

    /// Tracks selection so `layoutSubviews()` knows whether to redraw the shape or keep it cleared.
    private var isCurrent = false

    override func awakeFromNib() {
        super.awakeFromNib()

        faviconImage.layer.cornerRadius = 4
        faviconImage.layer.masksToBounds = true
        removeButton.type = .tabSwitcher
        removeButton.setImage(DesignSystemImages.Glyphs.Size16.close)
        removeButton.isPointerInteractionEnabled = true

        // Draw the selected-tab shape beneath the cell's content (favicon/label/close stay on top).
        // Disable implicit animations so the shape tracks frame changes (scroll/resize) crisply.
        selectedBackgroundLayer.actions = ["path": NSNull(), "fillColor": NSNull()]
        selectedBackgroundLayer.fillColor = UIColor.clear.cgColor
        contentView.layer.insertSublayer(selectedBackgroundLayer, at: 0)

        contentView.addInteraction(UIPointerInteraction(delegate: self))
    }
    
    @IBAction func onRemovePressed() {
        onRemove?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Defensive: a reused cell starts non-selected until `update()` says otherwise, so a stale
        // flare never lingers on a cell that's about to render an unselected tab.
        isCurrent = false
        selectedBackgroundLayer.path = nil
        selectedBackgroundLayer.fillColor = UIColor.clear.cgColor
        contentView.clipsToBounds = true
        layer.zPosition = 0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        if isPressed {
            layer.masksToBounds = false
            layer.shadowColor = UIColor.darkGray.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 5
        } else {
            // Selected cells must NOT clip — their flares extend horizontally past the cell bounds.
            layer.masksToBounds = !isCurrent
            layer.shadowColor = nil
            layer.shadowRadius = 0
        }

        updateSelectedShape()
    }

    /// Draws (or clears) the flared selected-tab shape and manages the clipping/z-order needed for the
    /// outward flares to show beyond the cell's own bounds and over its neighbours.
    private func updateSelectedShape() {
        guard isCurrent else {
            selectedBackgroundLayer.path = nil
            contentView.clipsToBounds = true
            layer.zPosition = 0
            return
        }

        // The flares spill outside the cell and into the inter-tab gap, so the cell and its content
        // view must not clip, and the cell must sit above its neighbours.
        contentView.clipsToBounds = false
        layer.zPosition = Metrics.selectedCellZPosition

        selectedBackgroundLayer.frame = contentView.bounds
        selectedBackgroundLayer.path = SelectedTabShape.path(
            forContentBounds: contentView.bounds,
            topCornerRadius: Metrics.topCornerRadius,
            bottomFlareRadius: Metrics.bottomFlareRadius,
            bottomOverlap: Metrics.bottomOverlap
        ).cgPath
    }

    func update(model: Tab,
                isCurrent: Bool,
                isNextCurrent: Bool,
                isFireModeEnabled: Bool,
                withTheme theme: Theme) {
        
        accessibilityElements = [label as Any, removeButton as Any]
        
        self.model?.removeObserver(self)
        
        self.model = model
        self.isFireModeEnabled = isFireModeEnabled
        model.addObserver(self)

        label.primaryColor = theme.barTintColor
        self.isCurrent = isCurrent
        if isCurrent {
            // Selected tab uses the custom flared shape (drawn in `updateSelectedShape()`), not the
            // storyboard's rectangular top/bottom backgrounds.
            topBackgroundView.backgroundColor = .clear
            bottomBackgroundView.backgroundColor = .clear
            selectedBackgroundLayer.fillColor = theme.omniBarBackgroundColor.cgColor
        } else {
            topBackgroundView.backgroundColor = .clear
            bottomBackgroundView.backgroundColor = .clear
            selectedBackgroundLayer.fillColor = UIColor.clear.cgColor
            separatorView.backgroundColor = theme.tabsBarSeparatorColor
        }

        labelRemoveButtonConstraint.isActive = isCurrent
        separatorView.isHidden = isCurrent || isNextCurrent
        removeButton.isHidden = !isCurrent

        // Reset/redraw the shape now that selection changed (handles cell reuse).
        setNeedsLayout()

        applyModel(model)
    }

    /// Configures the cell to render without a backing `Tab`.
    ///
    /// Used as a defensive fallback when the collection view requests a cell for an index that no
    /// longer exists in the tabs model (e.g. during a desync between the layout and the model). The
    /// cell is left visually empty and non-interactive; a subsequent refresh replaces it.
    func configurePlaceholder(withTheme theme: Theme) {
        self.model?.removeObserver(self)
        self.model = nil
        onRemove = nil

        label.primaryColor = theme.barTintColor
        label.text = nil
        label.accessibilityLabel = nil
        faviconImage.image = nil

        isCurrent = false
        topBackgroundView.backgroundColor = .clear
        bottomBackgroundView.backgroundColor = .clear
        selectedBackgroundLayer.fillColor = UIColor.clear.cgColor
        separatorView.backgroundColor = theme.tabsBarSeparatorColor

        labelRemoveButtonConstraint.isActive = false
        separatorView.isHidden = true
        removeButton.isHidden = true
        setNeedsLayout()
    }

    private func applyModel(_ model: Tab) {

        if model.link == nil {
            faviconImage.loadFavicon(forDomain: URL.ddg.host, usingCache: .tabs)
            updateEmptyTabLabel(for: model)
            removeButton.accessibilityLabel = closeButtonAccessibilityLabel(for: model)
        } else if model.isAITab {
            let aiChatTitle = UserText.omnibarFullAIChatModeDisplayTitle
            faviconImage.image = UIImage(resource: .duckAIDefault)
            if let conversationTitle = model.aiChatConversationTitle {
                label.text = "\(aiChatTitle) - \(conversationTitle)"
            } else {
                label.text = aiChatTitle
            }
            label.accessibilityLabel = UserText.openTab(withTitle: label.text ?? aiChatTitle, atAddress: "")
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: label.text ?? aiChatTitle, atAddress: "")
        } else {
            faviconImage.loadFavicon(forDomain: model.link?.url.host, usingCache: .tabs)
            label.text = model.link?.displayTitle ?? model.link?.url.host?.droppingWwwPrefix()
            label.accessibilityLabel = UserText.openTab(withTitle: model.link?.displayTitle ?? "", atAddress: model.link?.url.host ?? "")
            removeButton.accessibilityLabel = UserText.closeTab(withTitle: model.link?.displayTitle ?? "", atAddress: model.link?.url.host ?? "")
        }

    }
    
    private func updateEmptyTabLabel(for tab: Tab) {
        if isFireModeEnabled {
            label.text = tab.fireTab ? UserText.fireTabTitle : UserText.newTabTitle
            label.accessibilityLabel = tab.fireTab ? UserText.openNewFireTab : UserText.openNewTab
        } else {
            label.text = UserText.homeTabTitle
            label.accessibilityLabel = UserText.openHomeTab
        }
    }

    private func closeButtonAccessibilityLabel(for tab: Tab) -> String {
        if isFireModeEnabled {
            return tab.fireTab ? UserText.closeFireTab : UserText.closeNewTab
        }
        return UserText.closeHomeTab
    }
    
}

extension TabsBarCell: TabObserver {
    func didChange(tab: Tab) {
        guard tab != self.model else { return }
        applyModel(tab)
    }
}

extension TabsBarCell: UIPointerInteractionDelegate {

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        return .init(effect: .highlight(.init(view: contentView)))
    }

}

/// Builds the flared / "connected" active-tab outline: convex rounded TOP corners and OUTWARD-flaring
/// concave BOTTOM corners that widen the shape at its base so it merges into the omni bar below
/// (macOS Safari/Chrome active-tab look). Kept self-contained so the geometry is easy to reason about
/// and to gate (e.g. to iOS 26) later.
///
/// The shape is built in the cell's content-view coordinate space:
/// - top edge spans `[topCornerRadius, width - topCornerRadius]` then curves to the sides;
/// - the very bottom edge sits `bottomOverlap` below the content bounds and is widened by
///   `bottomFlareRadius` on each side, so it spans `[-bottomFlareRadius, width + bottomFlareRadius]`;
/// - each bottom corner is a concave quarter-arc connecting the vertical side to the widened bottom.
enum SelectedTabShape {

    static func path(forContentBounds bounds: CGRect,
                     topCornerRadius: CGFloat,
                     bottomFlareRadius: CGFloat,
                     bottomOverlap: CGFloat) -> UIBezierPath {
        let width = bounds.width
        let height = bounds.height
        let path = UIBezierPath()

        // Clamp so degenerate (very narrow / short) cells can't produce a self-intersecting path.
        let topR = max(0, min(topCornerRadius, width / 2, height))
        let flareR = max(0, min(bottomFlareRadius, width / 2))

        let bottomY = height + max(0, bottomOverlap)

        // Top-left corner start.
        path.move(to: CGPoint(x: topR, y: 0))
        // Top edge.
        path.addLine(to: CGPoint(x: width - topR, y: 0))
        // Convex top-right corner.
        path.addArc(withCenter: CGPoint(x: width - topR, y: topR),
                    radius: topR,
                    startAngle: .pi * 3 / 2,
                    endAngle: 0,
                    clockwise: true)
        // Right side straight down to where the concave flare begins.
        path.addLine(to: CGPoint(x: width, y: bottomY - flareR))
        // Concave bottom-right flare: curves down and OUTWARD to (width + flareR, bottomY).
        // Center is outside the shape (lower-right); sweeping 180°→90° counterclockwise (y-down)
        // produces the concave fillet that flares the base outward.
        path.addArc(withCenter: CGPoint(x: width + flareR, y: bottomY - flareR),
                    radius: flareR,
                    startAngle: .pi,
                    endAngle: .pi / 2,
                    clockwise: false)
        // Widened bottom edge.
        path.addLine(to: CGPoint(x: -flareR, y: bottomY))
        // Concave bottom-left flare: mirror of the right one, curving up and inward to the left side.
        path.addArc(withCenter: CGPoint(x: -flareR, y: bottomY - flareR),
                    radius: flareR,
                    startAngle: .pi / 2,
                    endAngle: 0,
                    clockwise: false)
        // Left side straight up to the top-left corner.
        path.addLine(to: CGPoint(x: 0, y: topR))
        // Convex top-left corner.
        path.addArc(withCenter: CGPoint(x: topR, y: topR),
                    radius: topR,
                    startAngle: .pi,
                    endAngle: .pi * 3 / 2,
                    clockwise: true)
        path.close()
        return path
    }
}
