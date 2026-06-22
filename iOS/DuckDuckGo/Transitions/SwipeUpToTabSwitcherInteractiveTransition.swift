//
//  SwipeUpToTabSwitcherInteractiveTransition.swift
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

import UIKit
import Core
import os.log

/// Custom interaction controller for the free-form swipe-up-to-tab-overview gesture.
///
/// Unlike `UIPercentDrivenInteractiveTransition` (which only scrubs a predetermined keyframe path), this
/// controller is driven *manually* so the dragged page preview can follow the finger in 2D and scale
/// down with vertical progress, then snap to its destination grid cell on commit. The presented tab
/// switcher stays a real `present(...)`ed VC; this just replaces the percent-driven interactor.
///
/// Frame geometry (initial full-content frame, destination cell frame, settled image frame) is produced
/// by the `From*` animator's `prepareInteractivePreview(...)`, so the snap lands pixel-identical to the
/// non-interactive button-tap transition. The overview behind the card blurs more the further up you
/// drag and sharpens on release.
final class SwipeUpToTabSwitcherInteractiveTransition: NSObject, UIViewControllerInteractiveTransitioning {

    enum Constants {
        /// Smallest scale the dragged card shrinks to at full vertical progress. Tunable for feel.
        static let minScale: CGFloat = 0.5
        /// Base snap duration on release.
        static let snapDuration: TimeInterval = 0.35
        /// Floor/ceiling for the velocity-scaled commit duration after a flick.
        static let minCommitDuration: TimeInterval = 0.18
        static let maxCommitDuration: TimeInterval = 0.40
        /// Spring damping for the *cancel* (return-to-page) snap — high, so it settles calmly without a
        /// bounce (a bounce on the way back to the page feels wrong).
        static let springDamping: CGFloat = 0.86
        /// Spring damping for the *commit* snap into the destination cell — lower than `springDamping`
        /// to give a tasteful little settle/bounce as the card lands. Tunable for feel.
        static let commitSpringDamping: CGFloat = 0.74
        /// Multiplier turning the flick's vertical speed into the commit spring's initial velocity, so a
        /// harder flick lands with a touch more energy. Capped by `maxCommitInitialSpringVelocity`.
        static let commitInitialSpringVelocityFactor: CGFloat = 0.0009
        static let maxCommitInitialSpringVelocity: CGFloat = 3.0

        // MARK: Blur (inverted: heaviest at the bottom, eases as the finger rises; only commit clears it)

        /// Blur fraction (0...1 of the property animator) at the very start of the drag — the heaviest
        /// the overview gets. 1.0 = the full `.systemThinMaterial`; ~0.7 keeps it visibly frosted at the
        /// bottom while leaving headroom so the grid reads clearly once it eases to the floor.
        static let maxBlur: CGFloat = 0.7
        /// Floor the blur eases down to by ~⅓ of the way up: light enough that the grid is clearly
        /// legible, but it never fully clears mid-drag (only the commit sharpens to 0) so a little
        /// frosting remains over the overview.
        static let minBlurDuringDrag: CGFloat = 0.10
        /// Smoothstep window (in *blur progress*, 0 = bottom, 1 = top) over which the blur eases from
        /// `maxBlur` down to `minBlurDuringDrag`. Below `blurEaseStart` it stays heavy (grid not yet
        /// legible at the very bottom); by `blurEaseEnd` it has reached the floor. With the 0.9 reference
        /// below, `blurEaseEnd ≈ 0.35` puts the floor at ≈⅓ of the screen height, so the grid is clearly
        /// legible by ~⅓ of the way up while still starting heavy at the bottom.
        static let blurEaseStart: CGFloat = 0.05
        static let blurEaseEnd: CGFloat = 0.35
        /// Fraction of the full content/screen height the finger must travel for blur progress to reach
        /// 1. Bigger than the visual (card-shrink) reference; combined with `blurEaseEnd ≈ 0.35` the blur
        /// reaches its floor at roughly ⅓ of the screen height.
        static let blurProgressReferenceFraction: CGFloat = 0.9
    }

    private var transitionContext: UIViewControllerContextTransitioning?
    /// The `From*` animator that built the preview; bypassed for `animateTransition`, used only for setup.
    private var animator: (UIViewControllerAnimatedTransitioning & SwipeUpInteractiveTransition)?
    private var preview: SwipeUpInteractivePreview?
    private weak var toView: UIView?
    /// The presented tab overview, retained weakly so `finish()`/`cancel()` can restore the dragged tab's
    /// hidden cell (Update 2b). Weak because UIKit owns the presented VC; the transition context also
    /// vends it, but caching it lets the completion blocks reach it without re-querying a torn-down context.
    private weak var toVC: TabSwitcherViewController?

    private var blurView: UIVisualEffectView?
    private var blurAnimator: UIViewPropertyAnimator?

    /// Latest finger translation, applied scale, and morph progress, so the commit/cancel snap can compute
    /// the card's exact current visual rect (bottom-centre anchor) and re-pin its subviews at the same morph
    /// state when baking the transform into `frame` — both flicker-free.
    private var lastTranslation: CGPoint = .zero
    private var lastScale: CGFloat = 1
    private var lastProgress: CGFloat = 0

    // MARK: UIViewControllerInteractiveTransitioning

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        Logger.swipeUpToTabSwitcher.debug("interactive.start")
        self.transitionContext = transitionContext

        let container = transitionContext.containerView

        guard let toVC = transitionContext.viewController(forKey: .to) as? TabSwitcherViewController,
              let fromVC = transitionContext.viewController(forKey: .from) as? MainViewController else {
            Logger.swipeUpToTabSwitcher.debug("interactive.start: missing to/from VC — completing immediately")
            finishImmediatelyAsCancel()
            return
        }
        self.toVC = toVC

        let finalFrame = transitionContext.finalFrame(for: toVC)
        toVC.view.frame = finalFrame
        // Fix 1: render the overview during the whole drag (not just on commit). The card covers it at
        // full size and reveals it — blurred by `blurView` — as it shrinks, so the blur samples the REAL
        // grid, not the opaque `solidBackground`. `cancel()` fades it back to 0 as the page returns.
        toVC.view.alpha = 1
        toVC.prepareForPresentation()
        toView = toVC.view

        // Blur layer over the overview, scrubbed via `fractionComplete`. Inverted Safari-style feel:
        // heaviest at the bottom (`maxBlur`) and easing as the finger rises, so you see more of the
        // overview the higher you go; only commit sharpens it fully. `.systemThinMaterial` reads well over
        // the overview's light-gray background; revisit on-device (try `.regular`/`.systemMaterial`).
        let blurView = UIVisualEffectView(effect: nil)
        blurView.frame = finalFrame
        self.blurView = blurView

        let blurAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            blurView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        blurAnimator.pausesOnCompletion = true
        blurAnimator.fractionComplete = Constants.maxBlur // heaviest at the start of the drag
        self.blurAnimator = blurAnimator

        // Build the dragged card via the From* animator's shared setup (web or NTP picked by surface).
        let animator: (UIViewControllerAnimatedTransitioning & SwipeUpInteractiveTransition)
        if fromVC.newTabPageViewController != nil {
            animator = FromHomeScreenTransition(mainViewController: fromVC, tabSwitcherViewController: toVC)
        } else {
            animator = FromWebViewTransition(mainViewController: fromVC, tabSwitcherViewController: toVC)
        }
        self.animator = animator

        guard let preview = animator.prepareInteractivePreview(finalFrame: finalFrame) else {
            // No preview/tab/layout — fall back to a plain fade-in so we never get stuck mid-transition.
            // (Alpha was set to 1 above for the normal drag path; reset to 0 here so this fade is visible.)
            Logger.swipeUpToTabSwitcher.debug("interactive.start: prepareInteractivePreview returned nil — fading switcher in")
            toVC.view.alpha = 0
            container.addSubview(toVC.view)
            UIView.animate(withDuration: TabSwitcherTransition.Constants.duration) {
                toVC.view.alpha = 1
            } completion: { _ in
                transitionContext.completeTransition(true)
            }
            return
        }
        self.preview = preview

        // Update 2b: hide the dragged tab's real cell in the overview for the whole transition, so the
        // dragged card is the only visible copy of that tab until it lands (zero doubling/seam). Done after
        // `prepareForPresentation()` + the scroll-to-current-tab inside `prepareInteractivePreview` so the
        // cell exists and is positioned. Restored in BOTH `finish()` and `cancel()` completion blocks.
        //
        // Robustness (hidden-cell race): the scroll-to-current-tab above applies a new content offset but
        // leaves cell realization PENDING, so the current cell may not be realized at its index path yet.
        // Force the layout pass HERE — after the scroll, before the hide — so the post-scroll visible cells
        // are realized when `setTransitioningTabCellHidden` sweeps them (it also flushes layout itself, so
        // this is belt-and-suspenders to make the ordering guarantee explicit at the call site).
        toVC.view.layoutIfNeeded()
        toVC.setTransitioningTabCellHidden(true)

        // Z-order, bottom → top: solidBackground (hides the from-VC) under the overview + blur under the
        // dragged card. The card (`imageContainer`) now holds the header strip + snapshot holder as its own
        // subviews (structural mirror of the cell), so the border/rounded corners frame the whole card —
        // header included. The presenting VC's real content sits below the (transparent) container.
        container.addSubview(preview.solidBackground)
        container.addSubview(toVC.view)
        container.addSubview(blurView)
        container.addSubview(preview.imageContainer)

        // The card is positioned by `initialContainerFrame` and the drag only mutates `transform`
        // (mutating `frame` while transformed is undefined in UIKit). The transform scales the card about
        // its own BOTTOM-CENTRE and translates by the finger, so the bottom edge stays put as the card
        // shrinks and rides the finger — like lifting the page by its bottom edge (the swipe starts on
        // the bottom bar), instead of the card drifting up off the finger. The commit/cancel snap
        // reconstructs the card's exact current rect from `lastTranslation`/`lastScale` (same bottom-centre
        // anchoring) and animates `frame` from there, so there is no flicker when the transform is cleared.
        preview.imageContainer.frame = preview.initialContainerFrame
        preview.imageContainer.transform = .identity
        // Progress 0 = full-bleed page: the snapshot holder covers the whole card (corner 0), the page fills
        // it, and the header is pinned to the top but fully transparent — so the page is edge-to-edge with no
        // visible header. As the drag rises the holder insets below the (fading-in) header and rounds.
        layoutCardSubviews(preview, progress: 0)
        preview.homeScreenSnapshot?.alpha = 1
        preview.cardHeader.alpha = 0
        lastTranslation = .zero
        lastScale = 1
        lastProgress = 0
        Logger.swipeUpToTabSwitcher.debug("interactive.start: ready initial=\(String(describing: preview.initialContainerFrame), privacy: .public) cell=\(String(describing: preview.destinationCellFrame), privacy: .public) overviewAlpha=\(Double(toVC.view.alpha), privacy: .public) blur=\(Double(self.blurAnimator?.fractionComplete ?? 0), privacy: .public)")
    }

    // MARK: Driving the drag

    /// Called from the gesture's `.changed`. Moves the card under the finger (`translation`), shrinks it
    /// with `verticalProgress`, ramps the corner/border, and scrubs the overview blur (inverted: heaviest
    /// at the bottom, eases up as the finger rises).
    func update(translation: CGPoint, verticalProgress: CGFloat) {
        guard let preview, let transitionContext else { return }
        let progress = min(max(verticalProgress, 0), 1)

        // Scale 1.0 → minScale as the drag rises, anchored about the card's BOTTOM-CENTRE, then translated
        // by the finger: T(translation) · T(0, +h/2) · S(scale) · T(0, -h/2). The bottom edge stays at
        // `initialContainerFrame.maxY` while the top comes down, and tracks the finger in x and y. At
        // (translation == .zero, scale == 1) this collapses to identity, so there is no start jump.
        let scale = 1.0 - (1.0 - Constants.minScale) * progress
        lastTranslation = translation
        lastScale = scale
        lastProgress = progress
        let halfHeight = preview.initialContainerFrame.height / 2
        preview.imageContainer.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            .translatedBy(x: 0, y: halfHeight)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: 0, y: -halfHeight)

        // Card corner + border ramp in lockstep with progress (preserves the existing settled-cell look).
        // The card clips its subviews, so the border + rounded corners frame the WHOLE card (header strip +
        // snapshot holder) — fixing the missing top border where the header used to overlay the card edge.
        preview.imageContainer.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius * progress
        preview.imageContainer.layer.borderWidth = TabViewCell.Constants.selectedBorderWidth * progress

        // Header fades in; snapshot holder insets below it and rounds all four corners — all driven off the
        // same `progress` so the card morphs into the cell in lockstep with the border/corner ramp.
        preview.cardHeader.alpha = progress
        layoutCardSubviews(preview, progress: progress)

        // NTP cross-fade: snapshot carries the start, the crisp centred logo carries the top of the drag
        // (also dodges the Dax-logo squeeze). No-op for web (homeScreenSnapshot == nil, imageView.alpha
        // already 1 from setup defaults).
        if preview.homeScreenSnapshot != nil {
            preview.homeScreenSnapshot?.alpha = max(0, 1 - progress / 0.3)
            preview.imageView.alpha = min(1, max(0, (progress - 0.2) / 0.3))
        }

        // Inverted blur: heaviest at the bottom, easing toward `minBlurDuringDrag` so the grid is clearly
        // legible by ~⅓ of the way up (where you care about where you'll land). Driven off a separate,
        // near-full-height blur progress (not the card-shrink `verticalProgress`, which saturates at
        // mid-screen) so the ease window maps onto a predictable fraction of the screen height.
        let blur = currentBlurFraction()
        blurAnimator?.fractionComplete = blur
        transitionContext.updateInteractiveTransition(progress)

        // Log the overview alpha alongside the blur fraction so we can confirm the REAL grid (alpha 1) is
        // what's being blurred during the drag, not the opaque solid background (Fix 1).
        Logger.swipeUpToTabSwitcher.debug("interactive.update progress=\(Double(progress), privacy: .public) tx=\(Double(translation.x), privacy: .public) ty=\(Double(translation.y), privacy: .public) scale=\(Double(scale), privacy: .public) blur=\(Double(blur), privacy: .public) overviewAlpha=\(Double(self.toView?.alpha ?? 0), privacy: .public)")
    }

    /// Blur fraction for the current drag, inverted and eased: `maxBlur` at the bottom, smoothstepped down
    /// to `minBlurDuringDrag` between `blurEaseStart` and `blurEaseEnd` of the (near-full-height) blur
    /// progress. Stays at least `minBlurDuringDrag` for the whole drag — only commit sharpens to 0.
    private func currentBlurFraction() -> CGFloat {
        guard let preview else { return Constants.maxBlur }
        // Full-screen reference (overview height) scaled by `blurProgressReferenceFraction`, so the blur
        // keeps easing across the upper half rather than saturating at mid-screen like the card shrink.
        let fullHeight = max(blurView?.frame.height ?? preview.initialContainerFrame.height, 1)
        let reference = max(fullHeight * Constants.blurProgressReferenceFraction, 1)
        let blurProgress = min(max(-lastTranslation.y / reference, 0), 1)
        // Smoothstep 0→1 across the ease window, then map onto maxBlur→minBlurDuringDrag (inverted).
        let eased = smoothstep(Constants.blurEaseStart, Constants.blurEaseEnd, blurProgress)
        return Constants.maxBlur - (Constants.maxBlur - Constants.minBlurDuringDrag) * eased
    }

    /// Standard Hermite smoothstep: 0 below `edge0`, 1 above `edge1`, eased S-curve in between.
    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Commit / cancel

    /// Commit: snap the card from wherever the finger left it to its destination cell, sharpen the
    /// overview, fade the switcher fully in, then tear down. `verticalVelocity` (pt/s, negative = up)
    /// shortens the snap after a flick.
    func finish(verticalVelocity: CGFloat = 0) {
        guard let preview, let transitionContext, let toView else {
            finishImmediatelyAsCancel()
            return
        }
        let duration = commitDuration(verticalVelocity: verticalVelocity)

        // Fix 2: recompute the destination cell frame against the CURRENT layout. The overview is presented
        // with the tracker banner hidden (synchronous present); the count then arrives and the banner is
        // inserted as a section header, pushing every cell DOWN — after `destinationCellFrame` was captured
        // at gesture start. Snapping to the stale frame lands too high and jumps when the snapshot is removed.
        // Re-query now (the animator calls `layoutIfNeeded()` first), and fall back to the stored cell if nil.
        // The header strip + snapshot region are derived from the cell's SIZE (card-local), so recomputing
        // the cell frame is enough — the subviews land in the right place relative to the card on commit.
        let capturedCell = preview.destinationCellFrame
        let fresh = animator?.currentDestinationFrames()
        let targetCell = fresh?.cell ?? capturedCell
        let cellDeltaY = targetCell.minY - capturedCell.minY
        Logger.swipeUpToTabSwitcher.debug("interactive.finish duration=\(Double(duration), privacy: .public) v=\(Double(verticalVelocity), privacy: .public) capturedCell=\(String(describing: capturedCell), privacy: .public) freshCell=\(String(describing: targetCell), privacy: .public) cellDeltaY=\(Double(cellDeltaY), privacy: .public) recomputed=\(fresh != nil, privacy: .public)")

        // Bake the live transform into the card's frame (flicker-free) so we can animate `frame` to the
        // cell — the cell has a different aspect ratio than the page, which a single transform can't match.
        bakeCurrentTransformIntoFrame(preview)

        // End-state (progress 1) geometry for the card's subviews, derived from the destination cell size.
        let targetHolder = SwipeUpCardLayout.snapshotRegion(forCardSize: targetCell.size)
        let targetHeader = SwipeUpCardLayout.headerFrame(forCardSize: targetCell.size)

        // Lower damping than the cancel path so the card settles into the cell with a tasteful little
        // bounce, plus a small initial velocity carried over from the flick (capped) so a harder flick
        // lands with a touch more energy.
        let initialSpringVelocity = min(abs(verticalVelocity) * Constants.commitInitialSpringVelocityFactor,
                                        Constants.maxCommitInitialSpringVelocity)
        UIView.animate(withDuration: duration,
                       delay: 0,
                       usingSpringWithDamping: Constants.commitSpringDamping,
                       initialSpringVelocity: initialSpringVelocity,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            preview.imageContainer.frame = targetCell
            preview.imageContainer.layer.cornerRadius = TabViewCell.Constants.cellCornerRadius
            preview.imageContainer.layer.borderWidth = TabViewCell.Constants.selectedBorderWidth
            // Snapshot holder lands on the cell's preview region with all four corners rounded to
            // `previewCornerRadius`; the image/snapshot fill it. Fixes the upper-corner snap (Fix 3) and the
            // header overlap (Fix 2 — the snapshot now sits fully below the header strip).
            preview.snapshotHolder.frame = targetHolder
            preview.snapshotHolder.layer.cornerRadius = TabViewCell.Constants.previewCornerRadius
            let holderBounds = CGRect(origin: .zero, size: targetHolder.size)
            preview.imageView.frame = holderBounds
            preview.imageView.alpha = 1
            preview.homeScreenSnapshot?.frame = holderBounds
            preview.homeScreenSnapshot?.alpha = 0
            // Header snaps to the cell's top strip (full alpha) so when the snapshot is removed it coincides
            // exactly with the real cell's header — no empty space, no jump. It's inside the bordered card,
            // so the top border frames it (Fix 1).
            preview.cardHeader.frame = targetHeader
            preview.cardHeader.alpha = 1
            toView.alpha = 1
            self.blurAnimator?.fractionComplete = 0 // sharpen: land in a crisp overview
        } completion: { _ in
            // Update 2b: the card is gone now — reveal the real cell so the overview shows the tab again.
            self.toVC?.setTransitioningTabCellHidden(false)
            self.tearDown()
            transitionContext.finishInteractiveTransition()
            transitionContext.completeTransition(true)
        }
    }

    /// Cancel: animate the card back to full screen, clear corner/border/blur, hide the switcher, tear down.
    func cancel() {
        guard let preview, let transitionContext, let toView else {
            finishImmediatelyAsCancel()
            return
        }
        Logger.swipeUpToTabSwitcher.debug("interactive.cancel")

        bakeCurrentTransformIntoFrame(preview)

        UIView.animate(withDuration: Constants.snapDuration,
                       delay: 0,
                       usingSpringWithDamping: Constants.springDamping,
                       initialSpringVelocity: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            preview.imageContainer.frame = preview.initialContainerFrame
            preview.imageContainer.layer.cornerRadius = 0
            preview.imageContainer.layer.borderWidth = 0
            // Back to full-bleed: holder covers the whole card (corner 0), image/snapshot fill it, header
            // fades back out at the top edge — the page returns edge-to-edge with no visible header.
            self.layoutCardSubviews(preview, progress: 0)
            preview.homeScreenSnapshot?.alpha = 1
            preview.imageView.alpha = preview.homeScreenSnapshot != nil ? 0 : 1
            preview.cardHeader.alpha = 0
            toView.alpha = 0
            self.blurAnimator?.fractionComplete = 0
        } completion: { _ in
            // Update 2b: restore the dragged tab's cell so the overview is intact if it's revisited (the
            // page is what's shown after a cancel, but the flag must be cleared and the cell un-hidden).
            self.toVC?.setTransitioningTabCellHidden(false)
            self.tearDown()
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(false)
        }
    }

    // MARK: Helpers

    private func commitDuration(verticalVelocity: CGFloat) -> TimeInterval {
        guard verticalVelocity < -SwipeUpToTabSwitcher.flickVelocity else { return Constants.snapDuration }
        // Faster the harder the flick, clamped to a comfortable band.
        let speedup = min(1, (abs(verticalVelocity) - SwipeUpToTabSwitcher.flickVelocity) / 2000)
        return Constants.maxCommitDuration - (Constants.maxCommitDuration - Constants.minCommitDuration) * speedup
    }

    /// The card's exact on-screen rect for the current drag, reconstructed from the last translation+scale
    /// with the bottom-centre anchor (scale about bottom-centre + finger translate over
    /// `initialContainerFrame`). Used to bake the transform into `frame` for the commit/cancel snap.
    private func currentCardRect(_ preview: SwipeUpInteractivePreview) -> CGRect {
        let initial = preview.initialContainerFrame
        let size = CGSize(width: initial.width * lastScale, height: initial.height * lastScale)
        // Bottom-centre rides the finger: it sits at the card's original bottom-centre plus the finger's
        // translation. The shrink pulls the top edge down toward it (origin.y = bottomCentre.y - height).
        let bottomCenter = CGPoint(x: initial.midX + lastTranslation.x, y: initial.maxY + lastTranslation.y)
        return CGRect(x: bottomCenter.x - size.width / 2,
                      y: bottomCenter.y - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// Lays the card's subviews (header strip + snapshot holder) in the card's CURRENT bounds for the given
    /// morph `progress`, mirroring `TabViewGridCell`: the header is pinned to the top (full width,
    /// `cellHeaderHeight` tall) and the snapshot holder ramps from full-bleed (covers the whole card, corners
    /// 0) to the cell's preview region (inset below the header, all four corners `previewCornerRadius`). The
    /// image + NTP snapshot fill the holder. Frame-based (the card is driven by `transform` during the drag,
    /// so its `bounds` stays the initial size; on commit/cancel it's re-pinned against the baked bounds).
    private func layoutCardSubviews(_ preview: SwipeUpInteractivePreview, progress: CGFloat) {
        let p = min(max(progress, 0), 1)
        let cardSize = preview.imageContainer.bounds.size

        // Header strip: same top-pinned box at every progress (alpha is what fades it in).
        preview.cardHeader.frame = SwipeUpCardLayout.headerFrame(forCardSize: cardSize)

        // Snapshot holder: lerp full-bleed → preview region, and round all four corners 0 → previewCornerRadius.
        let fullBleed = CGRect(origin: .zero, size: cardSize)
        let region = SwipeUpCardLayout.snapshotRegion(forCardSize: cardSize)
        preview.snapshotHolder.frame = lerp(fullBleed, region, p)
        preview.snapshotHolder.layer.cornerRadius = TabViewCell.Constants.previewCornerRadius * p

        // Image + NTP snapshot fill the holder.
        let holderBounds = CGRect(origin: .zero, size: preview.snapshotHolder.bounds.size)
        preview.imageView.frame = holderBounds
        preview.homeScreenSnapshot?.frame = holderBounds
    }

    /// Component-wise linear interpolation between two rects.
    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }

    /// Reconstructs the card's exact on-screen rect from the last drag transform, clears the transform and
    /// sets `frame` to that rect, then re-pins the card's subviews so the bake is visually continuous: their
    /// container-local frames are scaled by `lastScale` (the drag's visual scale, now folded into the card's
    /// bounds) so they keep the same on-screen size/position they had under the transform. The commit/cancel
    /// spring then drives `frame`s + corner radii from here to the cell — needed because the cell has a
    /// different aspect ratio than the page, which a single transform can't match.
    private func bakeCurrentTransformIntoFrame(_ preview: SwipeUpInteractivePreview) {
        // Capture the subviews' current (unscaled, container-local) frames before the bounds change.
        let headerLocal = preview.cardHeader.frame
        let holderLocal = preview.snapshotHolder.frame

        let visualRect = currentCardRect(preview)
        preview.imageContainer.transform = .identity
        preview.imageContainer.frame = visualRect

        // Scale the captured local frames by the drag's visual scale so they stay put on screen.
        preview.cardHeader.frame = scaleRect(headerLocal, by: lastScale)
        preview.snapshotHolder.frame = scaleRect(holderLocal, by: lastScale)
        let holderBounds = CGRect(origin: .zero, size: preview.snapshotHolder.bounds.size)
        preview.imageView.frame = holderBounds
        preview.homeScreenSnapshot?.frame = holderBounds
    }

    /// Scales a rect's origin + size uniformly about the layer origin (the card's top-left), matching how the
    /// drag transform scaled the subviews before the transform is baked into the card's `frame`.
    private func scaleRect(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    private func tearDown() {
        preview?.solidBackground.removeFromSuperview()
        // `cardHeader` + `snapshotHolder` are subviews of `imageContainer`, removed with it.
        preview?.imageContainer.removeFromSuperview()
        blurView?.removeFromSuperview()
        blurAnimator?.stopAnimation(true) // avoid a leaked running property animator
        blurAnimator = nil
        blurView = nil
        preview = nil
        animator = nil
        toVC = nil
    }

    /// Last-resort teardown when we can't drive a real animation (missing context/preview).
    private func finishImmediatelyAsCancel() {
        // Update 2b: restore the dragged tab's cell on the fallback path too (it's a no-op if we never
        // hid it, e.g. when the start guard fails before the hide call).
        toVC?.setTransitioningTabCellHidden(false)
        let context = transitionContext
        tearDown()
        context?.cancelInteractiveTransition()
        context?.completeTransition(false)
    }
}
