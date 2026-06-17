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

**Unit tests.** Cover the pure `progress(forTranslation:reference:)` and
`shouldCommit(progress:velocity:)` helpers (flick at low progress commits; below-threshold lift cancels;
clamping). Run via the existing `iOS Unit Tests` scheme / `UnitTests` target with
`-only-testing:UnitTests/<Suite>` (per project memory).

