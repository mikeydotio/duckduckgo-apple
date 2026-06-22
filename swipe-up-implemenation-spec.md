# Interactive Swipe-Up to Open the Tab Overview (iOS)

## Context

`swipe-up-spec.md` describes a finger-tracking, fully reversible gesture that transitions the
current page into the all-tabs overview (the "tab switcher"). It is **not** a fire-and-forget
trigger — progress is bound to the finger and only finalized on release (commit vs. cancel by
position + velocity). Scope: **iPhone only**, **bottom address bar only**, additive (the tabs
button and every other entry point stay unchanged). Per the spec author's decision, v1 supports
**both web pages and the New Tab Page** as the starting surface. The whole feature ships behind a
new **internal/experimental feature flag** — no separate user setting; flag on = feature on.

Today the tab switcher is opened **non-interactively**: the tabs button runs
`requestTabSwitcher()` → `segueToTabSwitcher()` which `present(_, animated: true)`s
`TabSwitcherViewController` with a custom `UIViewControllerTransitioningDelegate`
(`TabSwitcherTransitionDelegate`) that vends a snapshot "zoom into the cell" animator
(`FromWebViewTransition` for web pages, `FromHomeScreenTransition` for the NTP). There is **no
interactive transition anywhere** in this flow yet. This project adds one.

## Approach (key decisions)

1. **Make the *existing* transition interactive — don't rewrite it.** Drive the existing
   `FromWebViewTransition` / `FromHomeScreenTransition` with a `UIPercentDrivenInteractiveTransition`.
   Their `UIView.animateKeyframes(.calculationModeLinear)` animations scrub cleanly under percent-driven
   interaction (UIKit pauses the container layer and scrubs `timeOffset`). The only thing blocking
   reuse is that each animator hard-codes `transitionContext.completeTransition(true)` — wrong on the
   cancel path. Changing it to `completeTransition(!transitionContext.transitionWasCancelled)` is
   behavior-preserving for the button tap (never cancelled → still `true`) and correct for the gesture.
   **Result: the gesture lands pixel-identical to the button tap, with near-zero new animation code.**
   (Fallback if on-device scrubbing shows artifacts: introduce dedicated linear-`UIView.animate`
   animator subclasses. Not expected to be needed.)

2. **Present synchronously on gesture start.** `segueToTabSwitcher` is `async` only because it
   `await`s `TabSwitcherTrackerCountViewModel.calculateInitialState(...)` before presenting. For 1:1
   tracking, `present(_, animated: true)` must run the instant the gesture passes threshold. Only the
   tracker *count* is async; present with the synchronous default state and let the VM refresh after
   appearance. Achieved by extracting a synchronous controller-builder and a new synchronous interactive
   entry point, leaving the button-tap async path untouched.

3. **Vend the interactor only during the gesture.** `TabSwitcherTransitionDelegate` gets a `weak`
   `activeInteractor` and implements `interactionControllerForPresentation(using:)`. Button taps never
   set it → returns `nil` → normal animated present (current behavior fully preserved).

4. **Mirror the existing gesture infrastructure.** A new pan-gesture file copies the shape of
   `MainViewController+UnifiedToggleInputSwipeTabs.swift` (recognizer subclass + install + factory +
   `@objc handle` + `shouldBegin`). Attached to the bottom-bar region (`toolbar` +
   `navigationBarContainer`). Coexists with the existing horizontal tab-swipe pan by axis exclusion.

**De-risked during research:** `tabSwitcherController` is declared `weak`
(`MainViewController.swift:242`), so a cancelled presentation releases the controller and the ref
auto-nils — the "tabs button soft-bricks after cancel" risk the design flagged is largely handled by
the language. We still null the interactor explicitly and verify on-device.

## 1. Feature flag

- **`iOS/Core/FeatureFlag.swift`** — add an enum case (near the other internal flags, e.g.
  `webScrollFreezeObservability`):
  ```swift
  /// Internal-only: interactive swipe-up from the bottom bar to open the tab overview
  /// (iPhone, bottom address bar only). https://app.asana.com/<this-project-task>
  case swipeUpToTabSwitcher
  ```
  and its `Config` in the `config` switch (mirror the `webScrollFreezeObservability` line exactly):
  ```swift
  case .swipeUpToTabSwitcher:
      Config(defaultValue: .internalOnly, source: .remoteReleasable(iOSBrowserConfigSubfeature.swipeUpToTabSwitcher))
  ```
  `.internalOnly` + default `supportsLocalOverriding: true` ⇒ on for internal users, off in
  production, and auto-listed in the debug **Feature Flags** menu for toggling on a sim/device.
- **`SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`** — add
  `case swipeUpToTabSwitcher` to `iOSBrowserConfigSubfeature`.

Runtime check idiom (already used in `MainViewController`): `featureFlagger.isFeatureOn(.swipeUpToTabSwitcher)`.

## 2. Make the transition interactive

**`iOS/DuckDuckGo/Transitions/TabSwitcherTransition.swift`** — extend `TabSwitcherTransitionDelegate`:
```swift
weak var activeInteractor: UIPercentDrivenInteractiveTransition?   // set only during the gesture

func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning)
        -> UIViewControllerInteractiveTransitioning? {
    return activeInteractor          // nil for button taps → non-interactive present (unchanged)
}
```
`animationController(forPresented:)` stays as-is — it already returns `FromHomeScreenTransition` when
`mainVC.newTabPageViewController != nil`, else `FromWebViewTransition`, so **both surfaces work**.
Do **not** implement `interactionControllerForDismissal` (the inverse interactive transition is out of scope).

**`iOS/DuckDuckGo/Transitions/WebViewTransition.swift`** and
**`iOS/DuckDuckGo/Transitions/HomeScreenTransition.swift`** — in the presentation animators
(`FromWebViewTransition`, `FromHomeScreenTransition`) replace the completion-block
`transitionContext.completeTransition(true)` with
`transitionContext.completeTransition(!transitionContext.transitionWasCancelled)`. (Apply the same to
the `To*` animators for correctness even though dismissal stays non-interactive.) Overlay teardown
(`solidBackground`/`imageContainer` removal) already runs unconditionally in completion — good for the
cancel path.

## 3. Synchronous present refactor

**`iOS/DuckDuckGo/MainViewController+Segues.swift`** (current `segueToTabSwitcher` at `:197-260`):
- Extract the controller-construction body (from `DuckAIGridContentResolver` through
  `tabSwitcherController = controller`) into a **synchronous** helper:
  ```swift
  private func makeTabSwitcherController(initialTrackerCountState: TabSwitcherTrackerCountViewModel.State,
                                         forceFireTabsTip: Bool) -> TabSwitcherViewController?
  ```
- The existing `async segueToTabSwitcher` keeps its `await calculateInitialState(...)`, then calls
  `makeTabSwitcherController(...)`, then `present(animated: true)` — **no behavior change**.
- Add the interactive entry point:
  ```swift
  func beginInteractiveTabSwitcherPresentation(interactor: UIPercentDrivenInteractiveTransition) -> Bool {
      guard tabSwitcherController == nil else { return false }
      hideAllHighlightsIfNeeded()
      guard let controller = makeTabSwitcherController(initialTrackerCountState: .hidden,
                                                       forceFireTabsTip: false) else { return false }
      tabSwitcherTransition.activeInteractor = interactor   // BEFORE present, so UIKit vends it
      present(controller, animated: true)
      return true
  }
  ```
  Use `TabSwitcherTrackerCountViewModel.State.hidden` as the synchronous initial state; the VM
  refreshes the real count on appearance (verify the VC already calls `refresh()`/`refreshAsync()` on
  appear — `TabSwitcherTrackerCountViewModel.swift` — and only add an explicit refresh if it does not).

**Preview snapshot:** the button path runs the *async* `updatePreviewForCurrentTab { … }` before
presenting; the interactive path cannot await it. The `From*` animators read either a **cached**
web-view preview (`previewsSource.preview(for:)`) or a **synchronous** live snapshot (NTP uses
`resizableSnapshotView(afterScreenUpdates: false)`). In the gesture's `.began`, before presenting,
capture the current surface synchronously (reuse the existing synchronous snapshot path; for a web view
fall back to the cached preview if a sync capture isn't readily available) so the first interactive
frame is fresh. Exact capture call to be finalized against `updatePreviewForCurrentTab`'s internals —
hard constraint: **must be synchronous**.

## 4. The gesture — new file `iOS/DuckDuckGo/Transitions/MainViewController+SwipeUpToTabSwitcher.swift`

Mirrors `MainViewController+UnifiedToggleInputSwipeTabs.swift`:
```swift
final class SwipeUpToTabSwitcherPanGestureRecognizer: UIPanGestureRecognizer {}

extension MainViewController {
    func installSwipeUpToTabSwitcherGesture() {
        guard featureFlagger.isFeatureOn(.swipeUpToTabSwitcher) else { return }
        viewCoordinator.toolbar.addGestureRecognizer(makeSwipeUpToTabSwitcherPanGesture())
        viewCoordinator.navigationBarContainer.addGestureRecognizer(makeSwipeUpToTabSwitcherPanGesture())
    }

    private func makeSwipeUpToTabSwitcherPanGesture() -> SwipeUpToTabSwitcherPanGestureRecognizer {
        let pan = SwipeUpToTabSwitcherPanGestureRecognizer(target: self,
                                                           action: #selector(handleSwipeUpToTabSwitcherPan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func shouldBeginSwipeUpToTabSwitcherPan(_ pan: UIPanGestureRecognizer) -> Bool {
        guard featureFlagger.isFeatureOn(.swipeUpToTabSwitcher),
              UIDevice.current.userInterfaceIdiom == .phone,            // iPhone only
              appSettings.currentAddressBarPosition.isBottom,           // bottom bar only
              tabSwitcherController == nil,                             // not already presenting
              presentedViewController == nil,                          // no modal up
              !omniBar.isTextFieldEditing                              // not editing the address bar
        else { return false }
        let v = pan.velocity(in: pan.view)
        return v.y < 0 && abs(v.y) > abs(v.x)                          // upward-vertical dominant
    }
}
```
Note: **no** `newTabPageViewController == nil` guard — both web and NTP surfaces are supported (the
delegate already picks the right animator).

**State machine** (`@objc func handleSwipeUpToTabSwitcherPan(_:)`), reference distance ≈
`viewCoordinator.contentContainer.bounds.height`, `progress = clamp(-translation.y / reference, 0, 1)`:
- `.began`: capture preview synchronously (§3); create `UIPercentDrivenInteractiveTransition`
  (`completionCurve = .easeOut`), store it strongly on `self.tabSwitcherInteractor`; fire the same
  open pixels as the button path **only on commit** (see `.ended`) — at `.began` optionally run
  `performCancel()` to match button behavior; call `beginInteractiveTabSwitcherPresentation(interactor:)`;
  if it returns `false`, drop the interactor and disable/re-enable the recognizer to bail.
- `.changed`: `tabSwitcherInteractor?.update(progress)`. (Reversal is handled natively — `update`
  just re-scrubs; repeated up/down within one gesture works with no special code.)
- `.ended`: commit if `velocity.y < -flickThreshold` (≈ 700–900 pt/s) **or** `progress >= commitProgress`
  (≈ 0.30–0.40). Commit → set `completionSpeed` (~1.0, ~1.2 on flick) and `finish()` + fire the
  open/daily pixels (extract a `fireTabSwitcherOpenedPixels()` helper from `requestTabSwitcher()` so
  button and gesture share it). Otherwise → `cancel()`. Then `tabSwitcherInteractor = nil`.
- `.cancelled`/`.failed`: `tabSwitcherInteractor?.cancel()`; `tabSwitcherInteractor = nil`.

Consider extracting the pure decisions — `progress(forTranslation:reference:)` and
`shouldCommit(progress:velocity:)` — as static funcs so they're unit-testable.

## 5. Wiring (`iOS/DuckDuckGo/MainViewController.swift`)

- Add stored property near `lazy var tabSwitcherTransition` (`:252`):
  `var tabSwitcherInteractor: UIPercentDrivenInteractiveTransition?` (strong owner during gesture).
- `gestureRecognizerShouldBegin` (`:6003`) — add a branch **before** the unified-input one:
  ```swift
  if let pan = gestureRecognizer as? SwipeUpToTabSwitcherPanGestureRecognizer {
      return shouldBeginSwipeUpToTabSwitcherPan(pan)
  }
  ```
- `shouldRecognizeSimultaneouslyWith` (`:5999`, currently returns `true` globally) — add axis exclusion
  so the new vertical pan and the existing horizontal `UnifiedInputSwipeTabsPanGestureRecognizer` never
  run together:
  ```swift
  if (gestureRecognizer is SwipeUpToTabSwitcherPanGestureRecognizer && otherGestureRecognizer is UnifiedInputSwipeTabsPanGestureRecognizer)
  || (gestureRecognizer is UnifiedInputSwipeTabsPanGestureRecognizer && otherGestureRecognizer is SwipeUpToTabSwitcherPanGestureRecognizer) {
      return false
  }
  return true
  ```
- Install: call `installSwipeUpToTabSwitcherGesture()` next to the existing
  `installSwipeTabsGesturesForUnifiedInput()` invocation
  (`MainViewController+UnifiedToggleInput.swift:124`). Verify that call site runs unconditionally
  during view setup; if it is itself behind unrelated UTI gating, install from the general view-setup
  path instead so the gesture is governed only by our feature flag.

## 6. Edge cases & risks

- **NTP support:** handled — `FromHomeScreenTransition` is already selected by the delegate and uses a
  synchronous live snapshot, so it drives interactively the same way.
- **Single tab:** supported; the animators already scroll to and target the single cell.
- **Repeated reversal mid-gesture:** native to `UIPercentDrivenInteractiveTransition.update`; no extra code.
- **Cancel cleanup:** `tabSwitcherController` is `weak` → auto-nils when the cancelled presentation is
  released; gesture handler nils `tabSwitcherInteractor`; delegate's `activeInteractor` is `weak`.
  **Verify on-device:** after a cancel, the tabs button still opens the switcher and there is no leaked
  overlay.
- **Tabs button tapped mid-gesture:** inert — `segueToTabSwitcher` guards `tabSwitcherController == nil`,
  which we set synchronously at gesture start; and `shouldBegin` blocks starting a gesture while a
  present is in flight.
- **Pan on `navigationBarContainer` vs. address-bar taps:** a `UIPanGestureRecognizer` only claims pans,
  and `shouldBegin` bails while editing; verify tap-to-edit on the address bar still works with the pan
  attached (if it interferes, attach only to `toolbar` + a thin band, or require-failure of the omnibar tap).
- **Tracker-count header:** presenting with `.hidden` then refreshing may pop the banner in a frame late;
  acceptable (it lives inside the tab-switcher view that fades in from alpha 0), and irrelevant in the
  common no-trackers case.

## File-by-file change list

**New**
- `iOS/DuckDuckGo/Transitions/MainViewController+SwipeUpToTabSwitcher.swift` — recognizer subclass,
  `installSwipeUpToTabSwitcherGesture()`, factory, `@objc handleSwipeUpToTabSwitcherPan(_:)`,
  `shouldBeginSwipeUpToTabSwitcherPan(_:)`, and the pure progress/commit helpers.

**Modified**
- `iOS/Core/FeatureFlag.swift` — new `case swipeUpToTabSwitcher` + its `Config`.
- `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift` — new
  `iOSBrowserConfigSubfeature.swipeUpToTabSwitcher`.
- `iOS/DuckDuckGo/Transitions/TabSwitcherTransition.swift` — `activeInteractor` +
  `interactionControllerForPresentation`.
- `iOS/DuckDuckGo/Transitions/WebViewTransition.swift` &
  `iOS/DuckDuckGo/Transitions/HomeScreenTransition.swift` — `completeTransition(!…transitionWasCancelled)`.
- `iOS/DuckDuckGo/MainViewController+Segues.swift` — extract `makeTabSwitcherController(...)`; add
  `beginInteractiveTabSwitcherPresentation(interactor:)`.
- `iOS/DuckDuckGo/MainViewController.swift` — `tabSwitcherInteractor` property; `gestureRecognizerShouldBegin`
  branch; `shouldRecognizeSimultaneouslyWith` axis exclusion; extract `fireTabSwitcherOpenedPixels()` from
  `requestTabSwitcher()`.
- `iOS/DuckDuckGo/MainViewController+UnifiedToggleInput.swift` (~`:124`) — call
  `installSwipeUpToTabSwitcherGesture()`.

## 7. UX polish during the drag

Two visual refinements layered on top of the working interactive transition. Both stay behind the
`swipeUpToTabSwitcher` flag and leave the button-tap path untouched.

### A. Fade out the whole bottom bar

As the page lifts toward the overview, the bottom bar (the address-bar container **and** the toolbar)
fades away so the chrome gets out of the content's way.

- **Both** `viewCoordinator.navigationBarContainer` and `viewCoordinator.toolbar` fade together —
  alpha 1 → 0 over `barFadeDuration` (0.2s). It is a **fade**, not a slide.
- **Hysteresis** stops boundary flicker: fade out once `progress` rises above
  `hideBarsAboveProgress` (0.05); fade back in once it drops below `showBarsBelowProgress` (0.03).
  A new stored `Bool` on `MainViewController`, `isBottomBarHiddenForSwipeUp` (beside
  `tabSwitcherInteractor`), tracks shown/hidden state so each fade fires only once per crossing
  (`updateBottomBarVisibilityForSwipeUp(progress:)`, driven from the pan's `.changed`).
- **Restore.** On **cancel** (`.ended` not committing, plus `.cancelled`/`.failed`) the bars fade back
  to alpha 1 so the chrome returns as the page snaps back, and the `Bool` resets. On **commit**
  (`finish()`) the bars stay hidden through the finish (the switcher takes over); they are reset to
  alpha 1 and the `Bool` cleared in the `beginInteractiveTabSwitcherPresentation` transition-coordinator
  completion — that runs behind the presented switcher (invisible) and guarantees correct chrome when
  the user later dismisses back to the page. Because that completion also runs on cancel, it doubles as
  a safety net.
- **Correctness:** fade `alpha`, **never** `isHidden`. UIKit uses alpha only for hit-testing the
  *start* of new touches, not the continuation of an active touch, so the in-flight pan keeps tracking
  after its host bar fades to 0; `isHidden` would drop the gesture mid-drag.

Lives in `iOS/DuckDuckGo/Transitions/MainViewController+SwipeUpToTabSwitcher.swift` (thresholds + fade
helpers + `.changed`/`.ended`/`.cancelled` wiring) and `iOS/DuckDuckGo/MainViewController+Segues.swift`
(commit-path restore). The `Bool` is declared in `iOS/DuckDuckGo/MainViewController.swift`.

### B. Keep the NTP Dax logo circular during the drag

**Symptom:** on a fresh New Tab Page the circular Dax logo squeezed vertically as the drag progressed.
Invisible on the button tap (fast 0.2s) but obvious during the slow interactive drag. Web-page previews
are unaffected — this is **NTP-only**.

**Root cause** (`FromHomeScreenTransition` in `iOS/DuckDuckGo/Transitions/HomeScreenTransition.swift`):
`prepareSnapshots` snapshots the whole NTP via `resizableSnapshotView` and pins
`homeScreenSnapshot.frame = imageContainer.bounds`. As `imageContainer` animates from the full-screen
aspect ratio down to the tab-switcher cell's aspect ratio, the snapshot — a `.scaleToFill`-style view —
stretched **non-uniformly**, squeezing the circular logo inside it. The snapshot also faded over the
full drag (`relativeDuration 1.0`) while the crisp settled-state logo (`imageView`, contentMode
`.center`) only began fading in at `startTime 0.6`, so the stretched snapshot was on screen for most of
the gesture.

**Fix** (scoped to `FromHomeScreenTransition`, so `FromWebViewTransition` and the button-tap NTP
transition are unchanged):
- Give `homeScreenSnapshot` `contentMode = .scaleAspectFill` + `clipsToBounds = true` so it keeps its
  contents proportional (cropping, not squeezing) while the container morphs; `imageContainer` already
  clips.
- Accelerate the snapshot's fade-out to `relativeDuration 0.3` and bring the `.center` logo's fade-in
  forward to `startTime 0.2` so the aspect-correct logo carries the middle of the drag. The end state
  (snapshot at alpha 0, logo settled in the cell) is identical to the existing button-tap transition.

### C. Ramp a border on the dragged page preview

**Symptom:** on the light-gray all-tabs background a white page — a web page **or** the New Tab Page —
blends in, so you can't see the page edge or the already-animating rounded corners as the drag
progresses.

**Fix** (applied to **both** `FromWebViewTransition` in
`iOS/DuckDuckGo/Transitions/WebViewTransition.swift` and `FromHomeScreenTransition` in
`iOS/DuckDuckGo/Transitions/HomeScreenTransition.swift`):
- The dragged page-preview (`imageContainer`) ramps a **border** in lockstep with the corner radius
  that already animates over the full-span keyframe (`relativeStartTime 0`, `relativeDuration 1.0`):
  width grows `0 → TabViewCell.Constants.selectedBorderWidth` (2pt) as the radius grows `0 → 12pt`
  (`TabViewCell.Constants.cellCornerRadius`). Because `layer.borderWidth` animates inside a `UIView`
  animation block just like `cornerRadius`, the border width scrubs with the percent-driven drag, and
  since it shares `imageContainer.layer` it automatically follows the rounded corners.
- The max border matches the all-tabs **current-tab** cell: `selectedBorderWidth` and the current-tab
  border **color** `.decorationTertiary` (from `updateCurrentTabBorder` in `TabViewCell.swift`, the
  `isCurrent` / non-selection-mode branch). `borderColor` is set once before the keyframe block;
  `borderWidth` starts at 0 and is bumped to `selectedBorderWidth` inside the shared keyframe.
- At progress 1 the preview is a 12pt-corner, 2pt-bordered card matching the destination cell, then
  it's removed and the real cell shows — seamless. The shared keyframe also runs on the 0.2s
  button-tap present, which is fine/desirable since that path already lands on a bordered current-tab
  cell; there is no interactive-only branching.

### D. Free-form finger-tracking transition (engine rework)

**What changed and why.** The first cut (§2) drove the *existing* `From*` keyframe animation with a
`UIPercentDrivenInteractiveTransition` — it scrubbed a **fixed keyframe path**, so the dragged page
preview could only interpolate along the pre-baked full-screen→cell trajectory. That cannot let the
preview *follow the finger freely*. Per the product owner, the interaction model is now: the dragged
page preview moves in **2D** with the finger, **scales down** as you drag up, can be dragged around
(not locked to a path), and **snaps** to its destination cell on commit; the overview behind it
**blurs** more the higher you drag and **sharpens** on release. A percent-driven interactor only scrubs
a predetermined animation, so the engine moves to a **custom `UIViewControllerInteractiveTransitioning`**
driven manually. The tab switcher stays a real `present(...)`ed VC (committing lands in the live
overview); only the interaction controller is swapped — the button-tap and dismissal paths are
unchanged.

This **supersedes the percent-driven mechanism in §2** (the `completeTransition(!…transitionWasCancelled)`
edits there remain correct/harmless for the non-interactive button tap, which still runs the `From*`
`animateTransition` keyframes). Tweaks **A** (bottom-bar fade), **B** (NTP Dax-logo squeeze fix) and
**C** (border + corner ramp) are all preserved — re-expressed as manual per-frame drives instead of
keyframes.

**New file — `iOS/DuckDuckGo/Transitions/SwipeUpToTabSwitcherInteractiveTransition.swift`:**
`final class SwipeUpToTabSwitcherInteractiveTransition: NSObject, UIViewControllerInteractiveTransitioning`.
- `startInteractiveTransition(_:)`: installs the "to" tab-switcher view full-screen behind everything
  (alpha 0) and calls `prepareForPresentation()`; adds a `UIVisualEffectView(effect: nil)` over it for
  the blur; builds the dragged preview card (`solidBackground` + `imageContainer` + `imageView`) at the
  full-content initial frame and pre-scrolls the collection to the current tab — all via the `From*`
  animator's shared setup (see below), so geometry is **not duplicated**. Does **not** auto-animate.
- `update(translation:verticalProgress:)` (called each `.changed`): `imageContainer.transform =
  T(translation) · T(0,+h/2) · S(s) · T(0,−h/2)` — i.e. scale by `s` about the card's **bottom-centre**
  (offset `+h/2` from centre, `h = initialContainerFrame.height`) then translate by the finger — where
  `s` maps 1.0 (progress 0) → `minScale` (~0.5, tunable) at full vertical progress. The **bottom edge of
  the card rides the finger** (stays at `initialContainerFrame.maxY` and tracks the finger in x/y, top
  edge comes down as it shrinks) — like lifting the page by its bottom edge (the swipe starts on the
  bottom bar) — instead of the old centre anchor, where only the centre followed the finger so the card
  drifted up off the finger as it shrank. At `(translation == .zero, scale == 1)` the transform is
  identity → no start jump. Also ramps `cornerRadius 0→cellCornerRadius` and
  `borderWidth 0→selectedBorderWidth` with progress; cross-fades the NTP snapshot out to the crisp
  `.center` logo (the §B squeeze fix, re-expressed per-frame); scrubs the **inverted** blur (below);
  calls `context.updateInteractiveTransition(verticalProgress)`.
- **Inverted blur (Safari-style).** Blur is **heaviest at/near the start** of the drag and **decreases as
  the finger rises**, so you see more of the overview the higher you go (where you care about where
  you'll land). It is *not* the saturating card-shrink `verticalProgress`: `currentBlurFraction()` derives
  a **separate blur progress from `lastTranslation.y` against a near-full-height reference**
  (`blurView.height * blurProgressReferenceFraction`, bigger than the visual half-height reference) so it
  keeps easing across the **upper half** of the screen rather than maxing at mid-screen. A `smoothstep`
  between `blurEaseStart` and `blurEaseEnd` (of blur progress) maps `maxBlur → minBlurDuringDrag`: stays
  heavy early (grid not really visible ~1/3 up), noticeably less but still very blurry around halfway
  (grid starting to show), progressively clearer higher. It **never fully clears mid-drag** (floored at
  `minBlurDuringDrag`); **only commit sharpens to 0** (`finish()`'s `fractionComplete → 0`). The animator
  starts at `fractionComplete = maxBlur`.
- `finish(verticalVelocity:)` (commit): bakes the live transform into the card's `frame` (flicker-free,
  reconstructed from the last translation+scale with the **same bottom-centre anchoring**) — necessary
  because the destination **cell has a different aspect ratio** than the page, which a single transform
  can't match — then spring-animates `frame → destinationCellFrame`, `cornerRadius → cellCornerRadius`,
  `borderWidth → selectedBorderWidth`, `imageView → destinationImageViewFrame`, **sharpens** the blur
  (`fractionComplete → 0`), fades the switcher fully in; on completion tears down overlays, stops the
  blur animator (no leak), `finishInteractiveTransition()` + `completeTransition(true)`. Duration is
  **velocity-scaled** for a flick, and the commit snap uses a **lower spring damping**
  (`commitSpringDamping ~0.74`, vs the calmer `springDamping 0.86` for cancel) plus a small flick-derived
  `initialSpringVelocity` (capped) so the card **settles with a tasteful little bounce**.
- `cancel()`: bakes (bottom-centre anchored), then animates the card back to the full-content frame with
  the calm `springDamping` (no bounce on the way back), `corner/border → 0`, blur → 0, switcher
  alpha → 0; on completion tears down, `cancelInteractiveTransition()` + `completeTransition(false)`.
- **Blur technique:** `UIViewPropertyAnimator(duration: 1, curve: .linear)` toggling
  `blurView.effect = UIBlurEffect(style: .systemThinMaterial)`, `pausesOnCompletion = true`, scrubbed via
  `fractionComplete` (now driven by the inverted `currentBlurFraction()`, max at start);
  `stopAnimation(true)` on teardown. Blur style is a tuning knob (`.systemThinMaterial` vs
  `.regular`/`.systemMaterial` over the light-gray overview).

**Shared geometry (no duplication).** `FromWebViewTransition` and `FromHomeScreenTransition` adopt a new
`SwipeUpInteractiveTransition` protocol with `prepareInteractivePreview(in:finalFrame:)`, which reuses
their existing `tabSwitcherCellFrame` / `previewFrame` / `prepareSnapshots` / logo / border-colour setup
and returns a `SwipeUpInteractivePreview` (the live subviews + `initialContainerFrame`,
`destinationCellFrame`, `destinationImageViewFrame`). The snap therefore lands **pixel-identical** to the
button-tap end state. (`prepareSnapshots` lost its unused `transitionContext` parameter as part of this.)

**Delegate wiring (`TabSwitcherTransition.swift`).** `TabSwitcherTransitionDelegate.activeInteractor`
(typed `UIPercentDrivenInteractiveTransition`) becomes `activeInteractiveTransition` typed as the broader
`UIViewControllerInteractiveTransitioning`, returned from `interactionControllerForPresentation(using:)`.
`animationController(forPresented:)` still returns a `From*` animator (UIKit requires one; its
`animateTransition` is bypassed while the interaction controller drives, but it still provides
`transitionDuration` and runs the non-interactive button tap). Button taps leave it nil → unchanged.

**Gesture handler (`MainViewController+SwipeUpToTabSwitcher.swift`).** `tabSwitcherInteractor` is retyped
to the custom controller. `.began` creates it and hands it to `beginInteractiveTabSwitcherPresentation`.
`.changed` passes `gesture.translation(in:)` and a **visual** progress to `update(...)`: the commit
threshold + bar-fade keep the full-content-height reference (unchanged trigger), while the card
shrink/blur use a **half-height reference** (`visualProgressReferenceFraction = 0.5`) so visuals saturate
around mid-screen (the product owner's "~100% ≈ mid-screen" model; tunable). `.ended` keeps the existing
`shouldCommit(progress:verticalVelocity:)` decision + open pixels on commit + bottom-bar restore, calling
`finish(verticalVelocity:)` / `cancel()`. The commit-path bar restore + interactor release still run in
the `beginInteractiveTabSwitcherPresentation` transition-coordinator completion (verified).

**Tuning knobs (need on-device feel):** `minScale`, `visualProgressReferenceFraction`, the bottom-centre
anchor feel; the inverted-blur shape — `maxBlur`, `minBlurDuringDrag`, `blurEaseStart`/`blurEaseEnd`,
`blurProgressReferenceFraction`, and the blur style/intensity; the commit bounce — `commitSpringDamping`,
`commitInitialSpringVelocityFactor`/`maxCommitInitialSpringVelocity`; and the flick-scaled snap durations
(`snapDuration` / `min`/`maxCommitDuration` / `springDamping` for the calm cancel return).

### E. Three landing fixes (overview-visible blur, pixel-perfect commit, card header bar)

Three corrections on top of the free-form engine (§7.D). All three touch
`SwipeUpToTabSwitcherInteractiveTransition.swift`, `TabSwitcherTransition.swift`, `WebViewTransition.swift`
and `HomeScreenTransition.swift`; the button-tap and dismissal paths stay untouched.

**E.1 — The overview is visible (blurred) during the drag.** `startInteractiveTransition` previously set
`toVC.view.alpha = 0` for the whole drag, so the `UIVisualEffectView` blur sampled only the opaque
`solidBackground` → blurred gray, not the tabs. Fix: set `toVC.view.alpha = 1` in
`startInteractiveTransition` so the live grid renders during the drag; the card covers it at full size and
reveals it — blurred by `blurView` (already z-ordered between the overview and the card) — as it shrinks.
`finish()` keeps alpha 1 + blur → 0 (sharpen); `cancel()` fades alpha → 0 as the page returns; the
nil-preview fallback now resets alpha → 0 before its fade-in so that path still animates. The inverted-blur
`Constants` were later retuned in §7.F.1 (grid legible by ~⅓ up); the `currentBlurFraction()` curve is
unchanged. `interactive.update` / `interactive.start` log `overviewAlpha` next to `blur` so it's
confirmable that the real grid is what's blurred.

**E.2 — Commit snaps pixel-perfect on the real cell (no jump).** The overview is presented with the
tracker-count banner hidden (synchronous present; `initialTrackerCountState: .hidden`). The page controller
then fetches the count and inserts the "N trackers blocked" banner **as a collection-view section header**
(`referenceSizeForHeaderInSection` goes from `.zero` to `estimatedHeight`, `invalidateLayout()`), pushing
every grid cell DOWN — **after** `destinationCellFrame` was captured at gesture start. So the card snapped
too high and jumped down when the snapshot was removed. Fix: a new `SwipeUpInteractiveTransition` protocol
method `currentDestinationFrames() -> SwipeUpDestinationFrames?` (returns `cell` + `imageView` + `header`),
implemented by both `From*` animators by calling `collectionView.layoutIfNeeded()` (to flush a freshly
inserted banner) then re-querying `layoutAttributesForItem(at:)` and re-running their existing
`tabSwitcherCellFrame` / `previewFrame` / `headerFrame` math. The controller calls it at the top of
`finish()` and snaps to the fresh frames (cell + imageView + header), falling back to the stored ones if
nil; it logs `capturedCell`, `freshCell`, and `cellDeltaY` so the shift is visible (expected `cellDeltaY ≈
+estimatedHeight (50)` in the no-trackers→trackers case; `0` when the banner stays hidden).

**E.3 — The cell's top bar (favicon + title + X) on the dragged card.** The all-tabs cells have a
`cellHeaderHeight`-tall top bar (favicon, page title, close X) the card lacked → empty space at the top
when it landed. Fix: a new `SwipeUpCardHeaderView` (in `TabSwitcherTransition.swift`) replicates
`TabViewGridCell`'s header — favicon (16pt, leading 12, `faviconCornerRadius`), title (`daxFootnoteSemibold`
/ `.textPrimary`, `FadeOutLabel`), and a decorative `BrowserChromeButton(.tabSwitcher)` X with
`Size16.close` — laid out frame-based in `layoutSubviews` against the grid cell's metrics. It is populated
per surface (web favicon+title, Duck.ai icon+"Duck.ai", NTP Dax logo + home-tab title) by a shared
`makeSwipeUpCardHeader(for:)` factory on `TabSwitcherTransition`. The X is **decorative only** — not wired
to close anything (the card is transient). The controller adds it as a **sibling above `imageContainer`**
(not a subview — so the NTP header can sit *above* the preview-only container), starts it at alpha 0,
**fades it in with `progress` in lockstep with the border/corner ramp**, and rides it on the card's current
top edge each `.changed` (`headerFrame(forCardRect: currentCardRect(...))`). On commit it snaps to
`destinationHeaderFrame` (absolute tab-switcher-view space): for web that's the cell's top strip
(`cellFrame.minY`), for NTP it's the strip directly above the preview-region cell frame
(`cellFrame.minY - cellHeaderHeight`) — both recomputed from the fresh cell frame in E.2. Content is laid
out in the 44pt header-stack box pinned to the cell top, so favicon/title/X centre at the same y as the real
cell's header → pixel-match on handoff (the ±4pt header/preview boundary is the pre-existing 40-vs-44
transition approximation, unchanged). `cancel()` fades the header back out and returns it to the full-screen
card's top edge; `tearDown` removes it. Applies to **both** web and NTP.

### F. Final polish (legible blur by ~⅓ up; opaque cell-matching card; hide the dragged cell)

Three further refinements on top of §7.E. All stay behind the `swipeUpToTabSwitcher` flag; the button-tap and
dismissal paths are untouched.

**F.1 — Grid legible by ~⅓ of the way up (blur retune).** The blur previously stayed heavy until ~50% drag
(its ease window cleared too late). Per the product owner the grid should be clearly legible by ~⅓ of the way
up while still starting heavy at the very bottom. Only the inverted-blur `Constants` in
`SwipeUpToTabSwitcherInteractiveTransition.swift` change (the `currentBlurFraction()` math is unchanged):
`maxBlur 1.0 → 0.7` (≈30% less peak — visibly frosted but with headroom), `minBlurDuringDrag 0.18 → 0.10`
(light enough that the grid reads clearly at the floor), `blurEaseStart 0.30 → 0.05` and
`blurEaseEnd 0.85 → 0.35`. With the unchanged `blurProgressReferenceFraction 0.9`, the smoothstep reaches its
floor at `blurProgress ≈ 0.35` — i.e. ≈⅓ of the screen height — so the blur ramps from heavy at the bottom to
its legible floor by ~⅓ up, then holds (commit still sharpens to 0). All five remain tunable `Constants` for
the product owner to fine-tune.

**F.2 — Opaque, cell-matching card background (fix the "doubled title").** During the commit spring the card's
background behind the header strip was transparent (web) or the page `theme.backgroundColor` (NTP), so the real
cell's title showed through → the title looked doubled for a split second. The all-tabs grid cell's card is the
`RoundedRectangleView background`, whose colour is `.surfaceTertiary` (set in `TabViewCell.decorate()`); the
cell's header (favicon/title/X) is added to that `background`. Fix: set
`imageContainer.backgroundColor = UIColor(designSystemColor: .surfaceTertiary)` from the START of the drag in
**both** `prepareInteractivePreview` paths (`FromWebViewTransition` in `WebViewTransition.swift` — previously no
background; `FromHomeScreenTransition` in `HomeScreenTransition.swift` — previously `theme.backgroundColor`), so
the card is opaque on the same surface as the real cell throughout, not just at commit. The `SwipeUpCardHeaderView`
(in `TabSwitcherTransition.swift`) also gets `backgroundColor = .surfaceTertiary` in its `init`, so the header
strip is opaque over that surface and nothing shows through behind the title. (No `finish()` background change is
needed — the container is already the right colour the whole time.)

**F.3 — Hide the dragged tab's cell in the grid during the transition.** The dragged card and the dragged tab's
real overview cell were both visible, risking a doubled tab / seam at the landing. Fix: hide the
currently-dragged tab's cell in the overview's collection view for the whole transition and restore it on
completion. New API `TabSwitcherViewController.setTransitioningTabCellHidden(_:)` delegates to the visible
`TabSwitcherPageViewController`. **Robust to layout changes:** the page controller tracks a
`hiddenTransitioningIndexPath` (the current tab, `tabsModel.currentIndex`, section 0) and applies
`cell.isHidden = (indexPath == hiddenTransitioningIndexPath)` in **both** `collectionView(_:cellForItemAt:)` and
`collectionView(_:willDisplay:forItemAt:)` — so the tracker-count banner inserting mid-transition (which
invalidates layout and re-displays cells, undoing a one-shot `isHidden`) cannot un-hide it. On hide it also sets
the currently-visible cell's `isHidden = true` immediately; on restore it clears the flag and sets the visible
cell's `isHidden = false` (no `reloadItems`, which would be unsafe mid-batch-update). The interaction controller
(`SwipeUpToTabSwitcherInteractiveTransition.swift`) calls `setTransitioningTabCellHidden(true)` in
`startInteractiveTransition` (after `prepareForPresentation()` + the scroll-to-current-tab in
`prepareInteractivePreview`) and `setTransitioningTabCellHidden(false)` in **both** the `finish()` and `cancel()`
completion blocks **and** the `finishImmediatelyAsCancel()` fallback (no-op if never hidden). On commit the cell
reappears once the card is gone; on cancel it's cleaned up (the page is shown). This does **not** affect Fix
E.2's commit recompute (`layoutAttributesForItem` is position, not visibility) or the scroll-to-current-tab. An
`os_log` line is logged on both hide and restore.

**F.3 robustness fix — eliminate the hidden-cell timing race.** The original hide applied a one-shot
`collectionView.cellForItem(at: indexPath)?.isHidden = true`. That call returns **nil when the post-scroll
layout hasn't been flushed**: `setTransitioningTabCellHidden(true)` runs immediately after the
`scrollToItem(animated:false)` in `prepareInteractivePreview`, whose new content offset is applied but whose
cell realization is still pending, so the hide silently no-opped and the cell stayed visible mid-drag (the
"still visible" flake). A late reflow (the tracker banner) would then re-display it hidden, after which a
direct `cell.update(...)` (which resets `isHidden = false`) on the still-on-screen cell un-hid it again (the
"disappears then reappears" flake). Fixes:
1. `setTransitioningTabCellHidden(_:)` now **forces `collectionView.layoutIfNeeded()`** before acting, then
   **sweeps `indexPathsForVisibleItems`** (via a `sweepVisibleCells(hidingMatching:)` helper) and sets
   `isHidden` on the cell matching `hiddenTransitioningIndexPath` — instead of relying on a single
   `cellForItem(at:)` that can be nil. Restore (`false`) clears the flag and sweeps to un-hide.
2. The call site (`startInteractiveTransition`) also calls `toVC.view.layoutIfNeeded()` **after** the scroll
   and **before** the hide, making the "cells realized before the sweep" ordering explicit (belt-and-suspenders
   with (1)).
3. `didChange(tab:)` (the `TabObserver` path, which calls `cell.update(...)` directly and bypasses
   `cellForItemAt`/`willDisplay`) now **re-asserts** `isHidden = true` when the updated row is the hidden slot,
   so a favicon/title/preview load mid-drag can't un-hide the dragged cell. (`cellForItemAt` already applies the
   flag after `update(...)`; the tracker banner is a supplementary header whose re-display is handled by
   `willDisplay` and does not reconfigure the cell.)
4. Diagnostic `Logger.swipeUpToTabSwitcher` lines (all `privacy: .public`) were added so the race can be
   confirmed on-device: hide/restore log the index path, `currentIndex`, visible-cell count, and whether the
   matching cell was found at hide-time; `cellForItemAt`/`willDisplay`/the `didChange` re-assert each log when
   they hide the row.

The empty-gap / no-reflow behavior is unchanged: `isHidden` keeps the slot in the layout, so the other tabs do
not reflow — the dragged slot stays an empty gap for the whole interaction and the cell reappears exactly on
commit. Page-controller + index targeting is unchanged (`activePageController`, `tabsModel.currentIndex`,
section 0).

### G. Structural card rebuild — header inside the bordered card, snapshot insets below it (3 visual fixes)

Three visual issues with the committed free-form card, all in the card's top region, all fixed by rebuilding
the dragged card to **structurally mirror the all-tabs grid cell** (`TabViewCell` / `TabViewGridCell`)
instead of layering a header *over* a full-bleed snapshot:

1. **Top border was missing.** The header (favicon/title/X) was a **sibling** added *on top of* the card
   (`imageContainer`), covering the card's top border edge — so the ramped 2pt `.decorationTertiary` border
   didn't frame the top of the card. The real cell's header sits *inside* the rounded `background`, so the
   border frames it. **Fix:** the header is now a **subview of `imageContainer`**, and the card
   **clips to bounds**, so the border + rounded corners frame the WHOLE card, header included.
2. **Header overlapped the page.** The snapshot was full-bleed and the header sat over its top strip. In the
   cell the preview (`previewClipView`) sits *below* the header. **Decision: the page insets below the header**
   as the header fades in — full-bleed at progress 0, inset to below-header by progress 1. **Fix:** a new
   `snapshotHolder` (the structural analogue of `previewClipView`) ramps its frame from full-bleed (covers the
   whole card) to the cell's preview region.
3. **Snapshot upper corners snapped.** Only the lower corners rounded during the drag (the card clipped the
   lower corners but the upper ones met the header at radius 0), so the upper corners snapped at handoff.
   **Fix:** the `snapshotHolder` rounds **all four** corners, ramping `0 → previewCornerRadius`.

**Cell metrics matched** (from `TabViewCell.Constants` + `TabViewGridCell`): card background `.surfaceTertiary`,
`cellCornerRadius` **12**, continuous corners (`TabViewCell.decorate()` / `setupSubviews`); border 2pt
(`selectedBorderWidth`) `.decorationTertiary` for the current tab (`updateCurrentTabBorder()`); header strip
**`cellHeaderHeight` (40)** tall pinned to the card top (favicon 16pt / leading 12 / `faviconCornerRadius` 4,
title `daxFootnoteSemibold` / `.textPrimary`, 44pt close-X — `SwipeUpCardHeaderView`, mirroring the grid cell's
header stack); preview region inset `previewPadding` **4pt** on the sides + bottom and `cellHeaderHeight` from
the top (`TabViewGridCell.previewClipView`: width = background − 8, top = header bottom, bottom inset = 4),
corner radius `previewCornerRadius` **8**. (The real cell's `previewClipView` masks only the *lower* two
corners; the dragged holder rounds **all four** during the drag to kill the upper-corner snap — the snapshot is
removed on commit, so the brief 4-vs-2 difference at the handoff instant is imperceptible and far better than a
corner snapping from 0. The 40-vs-44 header/preview boundary is the pre-existing transition approximation,
unchanged.)

**New card structure (in the transition).** `imageContainer` is the **card** (the `background` analogue:
`.surfaceTertiary`, ramps `cornerRadius 0→12` + `borderWidth 0→2`, **clips to bounds**). Its subviews:
- `cardHeader` (`SwipeUpCardHeaderView`) — pinned to the card's top edge, full width, `cellHeaderHeight` tall,
  the TOP subview so the border frames it; alpha ramps `0→1`.
- `snapshotHolder` (`makeSnapshotHolder()` — the `previewClipView` analogue, clips to a ramping corner radius)
  below the header, holding `imageView` (web preview filling it `.scaleAspectFill`, matching the real cell; or
  the NTP `.center` Dax logo) and the NTP `homeScreenSnapshot`, each filling the holder.

The header was previously a sibling (a workaround so the NTP header could sit above a full-bleed preview). With
the snapshot now insetting below the header, the header becomes a subview of the card, which is what makes #1
work. `SwipeUpInteractivePreview` gains `snapshotHolder` and drops `destinationImageViewFrame` /
`destinationHeaderFrame` (the header strip + preview region are now derived **card-locally** from the cell's
*size* via `SwipeUpCardLayout.headerFrame(forCardSize:)` / `snapshotRegion(forCardSize:)`, shared by the
per-frame ramp and the commit snap), so `SwipeUpDestinationFrames` carries only `cell`.

**Morph ramp (lockstep with the existing border/corner/header ramps), driven by `progress`:** `layoutCardSubviews(_:progress:)`
lays the header (top strip) and lerps the holder `full-bleed → snapshotRegion` while rounding the holder
`0 → previewCornerRadius` (all four). Progress 0 = full-bleed page (header alpha 0, holder covers the whole card,
holder corner 0, card border 0, card corner 0); progress 1 = header alpha 1 + holder inset below it (top inset
`cellHeaderHeight`, 4pt sides/bottom) + holder corners 8 + card border 2 + card corner 12 — the exact cell
appearance. The card scales under the existing bottom-centre transform; header + holder are subviews so they
scale with it.

**Commit handoff stays pixel-perfect.** `finish()` recomputes the **full cell frame** via
`currentDestinationFrames()` (Fix E.2 path — flushes the tracker banner, re-queries layout), then snaps the card
to it and the subviews to their progress-1 end-states derived from that cell's size: `imageContainer.frame =
targetCell`, `snapshotHolder.frame = snapshotRegion(targetCell.size)` (corner `previewCornerRadius`),
`cardHeader.frame = headerFrame(targetCell.size)` (alpha 1), image/snapshot fill the holder. For **NTP** the
interactive path uses the **full** cell frame (`fullCellFrame(for:)`, header included) — *not*
`tabSwitcherCellFrame` which carves off the header for the button-tap keyframe path — because the card is now
the whole cell with the header as a subview. `bakeCurrentTransformIntoFrame` clears the drag transform and
re-pins the subviews by scaling their current container-local frames by `lastScale` (folding the visual scale
into the card's baked bounds), so the bake is visually continuous; the spring then drives every frame + corner
to the cell. `cancel()` reverses to progress 0 (full-bleed) via `layoutCardSubviews(_:progress: 0)`.

**Both surfaces.** Identical structure for web and NTP. NTP's `snapshotHolder` holds the home-screen snapshot +
the Dax-logo `.center` cross-fade (preserved) below the header; the NTP header shows the Dax logo + home-tab
title.

**Preserved (unchanged):** bottom-edge anchor + no-drift, scale, inverted blur, commit spring, pixel-perfect
snap recompute, hide-dragged-cell, NTP Dax cross-fade, bottom-bar fade, flick/threshold commit, open pixels,
cleanup, opaque `.surfaceTertiary` card bg, feature-flag + gating, button-tap path, `SwipeUpToTabSwitcher`
`os_log` logging.

**Files:** `SwipeUpToTabSwitcherInteractiveTransition.swift` (new `layoutCardSubviews` + `lerp`/`scaleRect`
helpers; header/holder driven card-locally in `update`/`finish`/`cancel`/`bake`; z-order no longer adds the
header separately), `TabSwitcherTransition.swift` (`SwipeUpInteractivePreview` + `SwipeUpDestinationFrames`
reshaped; new `SwipeUpCardLayout` enum + `makeSnapshotHolder()`; `SwipeUpCardHeaderView` re-documented as a card
subview), `WebViewTransition.swift` + `HomeScreenTransition.swift` (`prepareInteractivePreview` builds the
holder + parents the header/snapshot into the card; NTP `fullCellFrame(for:)` added; dead `headerFrame(forCellFrame:)`
removed).

## Verification / testing

**Manual (the primary verification — feel is the point of the project).** Build & run on an iPhone sim
(ad-hoc signing `CODE_SIGN_IDENTITY="-"` per project memory). Settings → set the address bar to
**Bottom**. Debug menu → **Feature Flags** → enable **swipeUpToTabSwitcher**. Then on a web page (and
separately on a fresh NTP), from the bottom bar:
- Slow drag up ~halfway, release → snaps back; tabs button still opens normally afterward.
- Slow drag past ~35%, release → commits into the overview.
- Quick flick up from rest → commits (velocity case).
- Drag up, drag fully back down, release → cancels.
- Rapidly reverse up/down within one gesture → view follows smoothly.
- Confirm: horizontal swipe-to-switch-tabs still works on the same bar; **top** address bar and **iPad**
  show no gesture; tapping the tabs button mid-drag is inert; single-tab case lands in a one-tab overview.
- **Bottom-bar fade (Tweak A):** at the start of the drag the whole bottom bar fades out; the gesture
  keeps tracking after it fades (it does not get cut off). On cancel the bar fades back in with the page;
  after committing then dismissing the switcher back to the page, the bar is fully visible (alpha 1).
- **NTP Dax logo (Tweak B):** on a fresh NTP, drag slowly to ~50% — the Dax logo stays circular (no
  vertical squeeze) throughout, and the settled overview cell looks identical to the button-tap result.
- **Overview visible & blurred (Fix E.1):** during the drag the real tab grid is visible behind the card,
  heavily frosted near the bottom and clearing as you rise — not a flat blurred gray. On commit it sharpens
  to a crisp overview; on cancel it fades out as the page returns.
- **Pixel-perfect commit (Fix E.2):** on a tab with trackers (so the "N trackers blocked" banner appears),
  release to commit — the card lands exactly on the destination cell with no downward jump when the
  snapshot is removed. Re-check with the banner absent (no-trackers tab) — still no jump. Web + NTP both.
- **Card header bar (Fix E.3):** as the card shrinks, the top bar (favicon + page title + X) fades in at
  the card's top; on landing it coincides exactly with the real cell's header (favicon, title, X all in
  place, no empty strip, no jump). Verify on a web page (real favicon + title) and on a fresh NTP (Dax logo
  + home-tab title). The X is inert (tapping it does nothing — the card is removed on commit anyway).
- **Legible blur by ~⅓ up (F.1):** at the very bottom of the drag the grid is heavily frosted; by ~⅓ of the
  way up the screen the grid is clearly legible (and stays legible higher up). Commit still sharpens to a
  crisp overview. Web + NTP.
- **No doubled title (F.2):** during the commit spring the card's header/title sits on an opaque,
  cell-matching surface — the real cell's title does NOT show through behind it (no doubled title for a
  split second). Verify web (real title) and NTP (home-tab title); light and dark mode (the surface adapts).
- **Dragged cell hidden (F.3):** during the whole transition the dragged tab's cell is hidden in the grid
  (only the card represents it — no second copy / seam). On **commit** the cell reappears once the card has
  landed (the overview shows the tab normally afterward). On **cancel** there's no leftover hidden cell if
  the overview is revisited. Re-check on a tab **with trackers** (so the "N trackers blocked" banner inserts
  mid-transition) — the cell stays hidden through the banner insertion and still reappears after commit.
  Web + NTP.
- **Structural card rebuild (G):** drag slowly up and watch the card's top region.
  - *Top border (Fix 1):* the 2pt border frames the WHOLE card including the header strip — the top edge of
    the card has a visible border above the favicon/title/X (the header is inside the bordered/rounded card,
    not overlaying its top edge).
  - *Header above the page (Fix 2):* as the header fades in, the page/snapshot **insets down** to sit fully
    below the header — no overlap (page is edge-to-edge at the very start, recedes below the header as you
    drag up).
  - *All-four-corner snapshot (Fix 3):* the snapshot's upper AND lower corners are rounded (ramping with the
    drag); at the handoff to the real cell there is **no upper-corner snap**.
  - On commit the card lands exactly on the destination cell (header strip + rounded preview region match the
    real cell, no jump). Verify on a **web page** (real favicon + title, preview fills the region) and a fresh
    **NTP** (Dax logo + home-tab title, centred Dax logo in the preview region, snapshot cross-fades to the
    logo). Re-check with the tracker banner present (no jump). Everything else — hide-cell, blur, bottom-edge
    anchor, scale, commit/cancel spring, bottom-bar fade — unchanged.

**Unit tests.** Cover the pure `progress(forTranslation:reference:)` and
`shouldCommit(progress:velocity:)` helpers (flick at low progress commits; below-threshold lift cancels;
clamping). Run via the existing `iOS Unit Tests` scheme / `UnitTests` target with
`-only-testing:UnitTests/<Suite>` (per project memory).

