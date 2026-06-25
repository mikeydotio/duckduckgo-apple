# iPad Top Chrome / iPadOS 26 Window Controls — Project Context & Hand-off

> **🔴 FUTURE AGENTS: KEEP THIS DOCUMENT UP TO DATE.** When you change any of the
> behavior, files, constants, commits, or known issues described here, update this
> file in the same change. It is the single source of truth for onboarding onto this
> work — stale context here will mislead the next agent. Line numbers drift; rely on
> the **symbol names** and update them when you touch the code.

> Status: active feature branch `bartosz/ipad-address-bar-scrolling` (off `main`).
> Repo: the `apple-browsers` monorepo (iOS app under `iOS/`). This doc lives at the
> checkout root next to [`hide-tab-bar-while-scrolling-spec.md`](hide-tab-bar-while-scrolling-spec.md).

---

## 1. What this project is

This branch contains **two related features** about the iPad browser's **top chrome**
(the tabs bar + the omni/address bar):

1. **Hide Tab Bar While Scrolling** — a user setting. Fully specced in
   [`hide-tab-bar-while-scrolling-spec.md`](hide-tab-bar-while-scrolling-spec.md).
   Controls whether the top chrome auto-hides on scroll or stays pinned. Behavior is
   **size-class driven** (regular width honors the setting; compact always auto-hides).
   Default **Off** (bar stays visible). Implemented & committed.

2. **iPadOS 26 inline window-controls layout** — make the top chrome sit **inline with
   the macOS-style traffic-light window controls** (Safari-style) instead of below the
   system's reserved title-bar band. This is the bulk of the recent work. Implemented;
   the final two pieces (tab-corner shape + full-screen hide) are **uncommitted pending
   on-device confirmation** at time of writing — see [§8 Status](#8-current-status--uncommitted-work).

They're on one branch but are **distinct features** — consider **separate PRs**.

---

## 2. iPadOS 26 windowing — essential background

On iPadOS 26 a window shows macOS-style **traffic-light window controls** (close/
minimize/resize) in the **top-leading corner**. Two modes:

- **`.minimal`** (legacy/compatibility): the system reserves a **title-bar safe-area
  band** for the controls and pushes app content **below** it. Wastes vertical space.
- **`.unified`** (what we use, Safari-style): controls sit **inline**; the app extends
  to the top and must **manually inset its own content** around the controls.

### Key APIs
- `UIWindowSceneDelegate.preferredWindowingControlStyle(for:)` → returns
  `UIWindowScene.WindowingControlStyle` (`.automatic` / `.minimal` / `.unified`).
- `view.layoutGuide(for: .margins(cornerAdaptation: .horizontal | .vertical))`, and the
  frame-based `view.directionalEdgeInsets(for:)` / `edgeInsets(for:)`.
  - **`.horizontal` corner adaptation → the LEADING inset** that clears the controls for
    a horizontal top bar. **Use this for horizontal clearance.** (`.vertical` gives a
    *top* inset and a near-zero leading value — wrong axis for our bars; using it was a
    real bug we hit.)
  - **Windowed-vs-full-screen detection:** the controls occupy leading space **only when
    windowed**, so `directionalEdgeInsets(for: .margins(cornerAdaptation: .horizontal)).leading > 0`
    ⇒ windowed; `== 0` ⇒ full screen. This is the reliable signal we use in multiple places.

### Can we move the window controls?
**No.** Their **position is system-owned** (always top-leading) — there is no API to
reposition them. We only control the **style** (`preferredWindowingControlStyle`) and lay
our own chrome out around them via the margins layout guides.

### Custom content gets NO automatic accommodation
Standard `UINavigationController` / SwiftUI `.toolbar` auto-shift around the controls.
Our tabs bar and omni bar are **custom** views, so we inset them **manually**.

---

## 3. The single revert switch

```swift
// SceneDelegate.swift
enum WindowControls {
    static let usesUnifiedStyle = true   // flip to false → legacy .minimal band, all
                                         // inline-layout code becomes inert.
}
```
`preferredWindowingControlStyle(for:)` returns `.unified` when this is `true`. Everything
in feature 2 is gated on `#available(iOS 26, *)` + `UIDevice.current.userInterfaceIdiom == .pad`
+ `WindowControls.usesUnifiedStyle`. Pre-iOS-26, iPhone, and the legacy style are unchanged.

---

## 4. Architecture & key files

> Line numbers are approximate and drift — search by symbol.

### Feature 1 — Hide Tab Bar While Scrolling (the setting)
- **Setting storage:** `AppUserDefaults.swift` — `hideTabBarWhileScrolling: Bool`
  (default **false**), UserDefaults key `com.duckduckgo.ios.hidetabbarwhilescrolling`,
  posts `Notifications.hideTabBarWhileScrollingChanged`. Protocol in `AppSettings.swift`;
  key enum in `Core/UserDefaultsPropertyWrapper.swift`; mock in
  `SharedTestUtils/.../AppSettingsMock.swift` (default false).
- **Setting UI:** `SettingsAppearanceView.hideTabBarWhileScrollingSetting()` — **iPad-only**
  row (`UIDevice.current.userInterfaceIdiom == .pad`). `SettingsViewModel.hideTabBarWhileScrollingBinding`
  (direct pass-through, no inversion). `SettingsState.AddressBar.hideTabBarWhileScrolling`.
  Label `UserText.settingsHideTabBarWhileScrolling` = "Hide Tab Bar While Scrolling".
- **Behavior (MainViewController.swift):**
  ```swift
  var canHideBars: Bool {
      if currentTab?.isError == true { return false }
      return !shouldPinChrome && !daxDialogsManager.shouldShowFireButtonPulse
  }
  private var shouldPinChrome: Bool {
      // The setting decides: ON ⇒ never pin (auto-hide on scroll).
      guard !appSettings.hideTabBarWhileScrolling else { return false }
      // OFF ⇒ pin. iPad honors it at ANY width (regular or compact); iPhone is unchanged
      // (pins only at regular width, e.g. large landscape).
      return UIDevice.current.userInterfaceIdiom == .pad
          || traitCollection.horizontalSizeClass == .regular
  }
  ```
  `revealChromeIfPinned()` un-hides the bar immediately when it becomes pinnable (setting
  change / size-class flip).
  - **The setting is the deciding factor (iPad).** OFF = stay visible at **any** window width
    (regular OR compact); ON = auto-hide on scroll. This **reverses** the spec's original
    "compact always auto-hides" rule — see the revised spec.
  - **iPad-scoped via an idiom check.** The toggle and the tab bar are iPad-only, so the
    at-any-width pinning is gated to `userInterfaceIdiom == .pad`. iPhone is unchanged (pins
    only at regular width; portrait / compact phones auto-hide as before). The earlier "decided
    solely by size class, no device check" rule **no longer holds** — the idiom check is deliberate.
  - **Semantics are a "Hide" toggle:** ON = hide, OFF = stay visible. Stored value has the
    same polarity as the toggle (no inversion). Be deliberate here.

### Feature 2 — iPadOS 26 inline window-controls layout
- **`SceneDelegate.swift`** — `WindowControls` enum + `preferredWindowingControlStyle(for:)`.
- **`MainView.swift`** (`MainViewFactory`) — constraint setup:
  - `constrainNavigationBarContainer()` / `constrainTabBarContainer()`: under
    iOS26+iPad+unified the top anchors to **`superview.safeAreaLayoutGuide.topAnchor`** (the
    window top) so the chrome rises inline with the controls. Else the legacy
    `.margins(cornerAdaptation: .vertical)` guide top.
  - `constrainStatusBackground()`: `StatusBackgroundView` top→superview.top,
    bottom→`navigationBarContainer.bottom`. (It's the background behind/above the chrome —
    the source of the "grey bar" bugs.)
- **`TabsBarViewController.swift`** — `updateWindowControlsInsetIfNeeded()` sets the tab
  strip's **leading inset** = `directionalEdgeInsets(for: .margins(cornerAdaptation: .horizontal)).leading`
  so tabs clear the controls. Also `flowLayout.sectionInset.left = TabsBarCell.Metrics.bottomFlareRadius`
  + a matching **leading-constraint pull-back** so the first tab's outward flare isn't
  clipped by the collection view and the tab body doesn't shift. **Contract: the flare's
  horizontal reach == `bottomFlareRadius`; both `sectionInset.left` and the pull-back read
  that constant — keep them in sync.**
- **`TabsBarCell.swift`** — `enum SelectedTabShape` draws the selected ("connected") tab:
  convex rounded **top** corners + **concave (inverted) bottom corners** that flare into
  the omni bar (fill = `omniBarBackgroundColor`). The selected cell is raised
  (`zPosition`) and un-clipped so flares show over neighbors. `enum Metrics` holds the
  tunable geometry (see [§7](#7-tunable-constants)).
- **`DefaultOmniBarView.swift` / `OmniBarView.swift`** — compact-window omni bar: when it's
  the topmost row beside the controls (tabs hidden), `setWindowControlsLeadingInset(_:)`
  gives it leading = `controls + Metrics.windowControlsContentGap` (replacing the base
  16pt), the field's centerX constraint is **deactivated** so it fills the width, and
  `updateVerticalSpacing()` uses reduced top / larger bottom padding so the field centers
  on the controls.
- **`MainViewController.swift`** — the orchestration:
  - `updateOmniBarWindowControlsInsetIfNeeded()` drives the omni-bar inset; called from
    `applyWidth()`, `traitCollectionDidChange`, `viewDidLayoutSubviews`,
    `onAddressBarPositionChanged`. Inset applies only when iOS26+iPad+unified+**tabs
    hidden**+**top** address bar; 0 otherwise.
  - `applyWidth()` → `applyLargeWidth/applySmallWidth/applyMinimalChromeWidth` toggle
    `tabBarContainer.isHidden` based on `AppWidthObserver.shared.isLargeWidth`
    (`isPad && currentWidth >= 678` / `minPadWidth`).
  - `updateStatusBarBackgroundColor(suppressTabsBarColorUntilStripVisible:)` colors
    `StatusBackgroundView`: grey `tabsBarBackgroundColor` **only when the tabs bar is
    actually visible** (`!tabBarContainer.isHidden`), else `omniBarBackgroundColor`. The
    `suppress…` flag avoids a grey flash on the compact→regular transition (see gotchas).
  - `updateNavBarConstant(_ ratio:)` does the scroll hide/show offset math, **clamped by
    `hiddenChromeFloorHeight`** so the chrome keeps a minimum band behind the controls when
    windowed. `hiddenChromeFloorHeight` returns 0 unless iOS26+iPad+unified+top-bar **AND**
    window controls are present (windowed); capped by `ChromeHideConstants.maxHiddenChromeFloorHeight` (64).

---

## 5. Build & test (this repo is finicky — follow exactly)

- **Scheme:** `iOS Browser` (NOT "DuckDuckGo"). **Project:** `iOS/DuckDuckGo-iOS.xcodeproj`.
- **Concrete simulator only** (never `generic/...`, or the WebKit-workaround script phase
  fails). Prefer an **iOS 26 iPad** sim so feature-2 code compiles in context. Discover via
  `xcrun simctl list devices available`.
- **Ad-hoc signing** (not `CODE_SIGNING_ALLOWED=NO`):
  ```
  xcodebuild build -project iOS/DuckDuckGo-iOS.xcodeproj -scheme "iOS Browser" \
    -destination 'platform=iOS Simulator,id=<UDID>' \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES -quiet
  ```
- **On-device behavior can't be verified headlessly** — windowed-mode traffic-light layout,
  the grey-bar flash, the tab-corner shape, and scroll-hide all need a human looking at an
  iPadOS 26 simulator/device in a **window** (Stage Manager / Split View). The owner
  (Bartosz) verifies visually and shares screenshots.
- **Pre-commit hook** runs `git add -u` (sweeps all modified tracked files). Use
  `git commit --no-verify` + explicit `git add <files>` when you need a precise subset.

---

## 6. Commit history (chronological, on this branch)

| Commit | What |
|---|---|
| `caca539588` | Original "Keep Address Bar Visible on iPad" setting (later renamed) |
| `7d2614d264` | Add the hide-tab-bar spec doc |
| `1918bed658` | Rename to **Hide Tab Bar While Scrolling**, invert to hide-semantics (default Off), make device-agnostic (size class, no device check) |
| `3a6903b8bc` | Lay out iPad top chrome **inline** with iPadOS 26 window controls (`.unified` + safe-area-top anchor + tab leading inset) |
| `320020e578` | Inset the omni bar past the controls in compact windows |
| `74f5adb58a` | Draw the active tab as a connected/flared shape |
| `4535cfcf4e` | Render the first tab's leading flare instead of clipping it (`sectionInset` + pull-back) |
| `e8df57fe33` | Compact omni-bar fill/alignment + grey-bar fix (status color keyed to tabs visibility) |
| `644684acaf` | Fix grey `StatusBackgroundView` flash on compact→regular resize (suppress-until-strip-visible) |
| `27088f1494` | Keep a chrome floor behind window controls when hiding on scroll |
| _(uncommitted)_ | Simple inverted **r10** tab corner; full-screen **full-hide** (floor only when windowed) |

---

## 7. Tunable constants

**`TabsBarCell.Metrics`** (active tab shape):
- `topCornerRadius = 12` — convex top corners.
- `bottomFlareRadius = 20` — the **inverted (concave) bottom-corner radius** AND the
  horizontal flare reach (the layout contract depends on this == the reach).
- `bottomOverlap = 4` — how far the shape drops below the cell to merge with the omni bar.
- `selectedCellZPosition = 1`.
- _History:_ the bottom corner went arc(12) → cubic-Bézier (too curvy) → slope+arc (too
  straight) → plain concave quarter-circle r10 → r15 → **r20** (current). The path math was
  always an exact, tangent-continuous quarter-circle — the radius bumps were purely to soften
  the curve (r10/r15 still read as edgy/janky). Keep it simple; the owner wants a literal
  inverted radius-20 corner, no Bézier. (Degenerate clamp engages only below 40pt tab width;
  min tab width is 120pt, so it never fires in practice.)

**`DefaultOmniBarView.Metrics`** (compact omni bar beside controls):
- `windowControlsContentGap = 8` — gap between controls and the omni bar's leading edge.
- `windowControlsContentTopPadding = 0` / `windowControlsContentBottomPadding = 16` —
  vertical centering on the controls (sum preserved for field height).

**`MainViewController.ChromeHideConstants`:**
- `maxHiddenChromeFloorHeight = 64` — safety cap on the hidden-chrome floor height.

---

## 8. Current status & uncommitted work

- **Committed & confirmed:** features 1 & 2 through `27088f1494` (inline chrome, compact
  omni-bar fill/alignment, grey-bar fixes, hide floor).
- **Latest branch work** (owner confirmed the update; committed grouped by concern):
  - `TabsBarCell.swift` — inverted tab corner radius bumped to **r20** (was r10→r15; earlier
    radii read as edgy/janky). Path geometry unchanged — exact quarter-circle.
  - `MainViewController.swift` — (1) **full-screen full-hide** (`hiddenChromeFloorHeight` returns
    0 in full screen via the `.horizontal).leading > 0` windowed gate); (2) `shouldPinChrome` now
    lets the **setting decide at any width on iPad** (compact no longer force-hides when the
    setting is OFF); iPhone unchanged.
  - `DefaultOmniBarView.swift` — **no net change.** A "symmetric padding" tweak for the compact
    omni bar was tried and reverted: the field must stay **vertically centered on the window
    controls** (the 0/16 push-up), so the file is back at its committed state.

---

## 9. Known issues / open items

- **Latent duplicate of the grey-bar bug** in `SiteThemeColorManager.applyThemeColor`: it
  still decides the chrome/status color from `horizontalSizeClass == .regular` rather than
  actual tabs-bar visibility. Only affects the **bottom address bar + website-theme-color**
  case (so it can't cause the top-bar flash we already fixed). Flagged as a background task;
  fix by mirroring the `!tabBarContainer.isHidden` approach used in
  `updateStatusBarBackgroundColor()`.
- **Hide floor is scoped to the TOP address bar.** With the address bar at the **bottom** on
  a unified iPad window, the top chrome (tabs bar only) would still hide fully. Open question
  whether to extend the floor there.
- **Two features on one branch** — likely want separate PRs (hide-tab-bar setting vs. the
  iPadOS 26 window-controls layout).
- **`hideTabBarWhileScrolling` toggle is iPad-only.** On iPad the setting now decides at any
  width; on iPhone the old size-class rule still applies, so a **large landscape iPhone (regular
  width) keeps the bar pinned** by default with no in-app toggle. The behavior is **no longer
  purely size-class-driven** — `shouldPinChrome` also checks the iPad idiom (see §4 Feature 1).

---

## 10. Gotchas & hard-won learnings

- **Size class flips before the tabs bar appears.** `horizontalSizeClass` becomes `.regular`
  at ~668pt, but the tabs bar only shows at `AppWidthObserver.isLargeWidth` (≥ **678**).
  Keying chrome color / floors off the size class (instead of `!tabBarContainer.isHidden` or
  the windowed signal) caused multiple grey-bar bugs. **Key off actual tabs-bar visibility.**
- **`.horizontal` vs `.vertical` corner adaptation matters.** Horizontal → leading inset
  (clears controls for a top bar); vertical → top inset. Using `.vertical` for leading
  clearance silently under-insets.
- **Recolor-before-relayout race.** Recoloring `StatusBackgroundView` grey synchronously
  when tabs un-hide, before the async `showBars()` lays the strip in, flashes a grey band.
  Fix: suppress grey until the strip is committed in the same async tick
  (`suppressTabsBarColorUntilStripVisible`).
- **`Logger` type-checker blow-up.** Don't `+`-concatenate multiple `Logger` string
  interpolations that each carry a `privacy:` specifier — it triggers "unable to type-check
  this expression in reasonable time." Build a plain `String` first, then log it in one
  interpolation. (Temporary diagnostics were used several times and then removed.)
- **First/leading tab flare clipping.** The active tab's outward flares extend past the cell;
  the collection view clips them at its leading edge. Solved with `sectionInset.left =
  bottomFlareRadius` + a leading-constraint pull-back (don't disable collection-view clipping
  wholesale — recycled cells spill).
- **Full screen ≠ windowed.** In full screen there are no controls and `.margins(...).top` is
  still non-zero (status bar), so scope checks alone don't disable controls-dependent layout
  there — gate on `.horizontal).leading > 0`.

---

## 11. QA checklist (feature 2; for feature 1 see the spec)

- [ ] Windowed iPad: tabs/omni bar sit **inline** with the traffic lights — no empty band above.
- [ ] First tab's leading bottom corner flares into the omni bar (not clipped/squared).
- [ ] Active tab's bottom corners are even **r20** concave curves matching the design.
- [ ] Compact window (tabs hidden): omni bar fills the width with ~8pt gap to the controls and is vertically centered on them.
- [ ] Compact iPad window + setting **Off** + scroll: omni bar **stays visible** (does not auto-hide); setting **On** → it auto-hides. iPhone unaffected.
- [ ] Resize slowly across the ~668–678 threshold both directions: **no grey flash** at the top.
- [ ] Setting ON + scroll, **windowed**: a controls-height chrome band stays put (tappable).
- [ ] Setting ON + scroll, **full screen**: chrome hides **completely** off-screen.
- [ ] Flip `WindowControls.usesUnifiedStyle = false`: reverts to the legacy reserved-band layout.
- [ ] No regressions: iPhone, pre-iOS-26 iPad, `.minimal`, bottom address bar, full screen.
