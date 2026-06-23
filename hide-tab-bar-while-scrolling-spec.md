# Hide Tab Bar While Scrolling — Feature Spec

> Status: Draft for hand-off. Implementation-agnostic (describes the feature and the setting, not how to build it in any specific codebase).

## Summary

Add a user setting, **"Hide Tab Bar While Scrolling,"** that controls whether the browser's tab bar auto-hides as the user scrolls a web page, or stays fixed and fully visible.

Today the tab bar always auto-hides on scroll. This feature makes that behavior user-controllable and brings it to **feature parity with Safari**: the bar stays visible in a normal (regular-width) window and only falls back to auto-hiding when the window gets narrow enough. The behavior is **device-agnostic** and driven by **window size class**, not by device model or any fixed width value.

This first version is **only** the setting and the show/hide behavior it controls. There is no minimized or partial bar state of any kind (see [Out of scope](#out-of-scope)).

## Motivation

- On larger windows, chrome that disappears on scroll feels like a scaled-up phone and wastes the available space.
- Keeping the bar visible means the current address is always shown and removes the "scroll back up to get the bar" friction.
- It closes a known competitive gap: Safari keeps the tab bar visible and lets users opt into hiding it. We want the same.

## Terminology

- **Tab bar** — the browser's top chrome as a whole: the address/URL field plus the row of open tabs and any inline controls. "The tab bar hides" means this entire top chrome slides out of view while scrolling.

## The setting

| | |
|---|---|
| **Label** | Hide Tab Bar While Scrolling |
| **Control** | Toggle (on / off) |
| **Location** | Browser settings, under the appearance / address-bar section |
| **Default** | **Off** — the tab bar stays visible |
| **Persistence** | Stored as a user preference; persists across app launches |

### What each state does

> This is a **"Hide…"** toggle, so the "on" state is the one that *hides* the bar. Be deliberate about this in the UI and code to avoid inverted-logic bugs.

- **On** → the tab bar **auto-hides** while scrolling down and reappears when the user scrolls up or reaches the top of the page (the conventional behavior).
- **Off** → the tab bar **stays fixed and fully visible**; page content scrolls underneath it.

(Both states are still subject to the window-size rule below.)

## Window size & size classes (Safari parity)

This is the core of the feature and the part to get right. The behavior is **device-agnostic** and decided **solely by the window's horizontal size class** — never by a device model and never by a hard-coded width number.

- **Regular-width window** (an iPad app at a normal/large window size — full screen or a wide split-view pane): the setting is honored.
  - Setting **Off** → tab bar stays fixed and visible.
  - Setting **On** → tab bar auto-hides on scroll.
- **Compact-width window** (the user has narrowed the window enough — e.g. a narrow split view or Slide Over): **always fall back to the default auto-hide behavior, regardless of the setting.** There isn't room to keep the bar pinned. This is exactly what Safari does.
- **Live size-class changes:** entering/leaving split view, resizing, or rotating can flip the size class at runtime. React immediately and without a relaunch — when a window becomes regular width with the setting Off, restore the bar right away; when it becomes compact, resume auto-hide.

> ⚠️ **Do not** gate this on a fixed window-width threshold/breakpoint, and **do not** target specific device models or screen sizes. Use the horizontal size class. Because size class already distinguishes wide vs. narrow windows on every device, no per-device logic is needed — e.g. a phone in portrait is compact and therefore simply keeps today's auto-hide behavior, with no special-casing.

## Acceptance criteria

- A toggle labeled **"Hide Tab Bar While Scrolling"** appears in the browser's appearance settings, defaulting to **Off**.
- In a **regular-width** window with the toggle **Off**, scrolling a long page never hides the tab bar.
- In a **regular-width** window with the toggle **On**, scrolling down hides the tab bar and scrolling up restores it.
- In a **compact-width** window, the tab bar auto-hides on scroll **regardless** of the toggle.
- Toggling the setting updates the live page immediately, including revealing a currently-hidden bar when switched **Off** in a regular-width window.
- Resizing/rotating between regular and compact width updates the behavior live (bar restored when it becomes regular + Off; auto-hide resumes when it becomes compact).
- The chosen value persists across app launches.
- No fixed width constant or device-model check is used to make these decisions — only the horizontal size class.

## Out of scope

Explicitly **not** part of this feature (previously explored, now dropped):

- The Safari-style minimized domain **"capsule"** and any partial/minimized bar state.
- Tap-to-expand / tap-to-edit affordances tied to a minimized bar.
- Inertia/momentum-scroll interactions specific to a minimized bar.
- Per-site or per-tab overrides.

## Open decisions

1. **Default value** — confirm **Off** (bar visible) by default.
2. **Setting visibility surface** — the *behavior* is purely size-class-driven and device-agnostic. Separately, decide where the *toggle* is shown: iPad only (recommended, where regular width is the norm), or on every device (a large phone in landscape is regular width too, so pure size-class behavior would keep its bar pinned — confirm that's acceptable or whether to hide the toggle there).
3. **Label & placement** — confirm the wording "Hide Tab Bar While Scrolling" and which settings section it lives in.
4. **Rollout** — ship default-on for everyone vs. a staged rollout / experiment.
5. **Analytics** — whether to record toggles and the resulting state.

## QA checklist

- [ ] Toggle appears with the correct label in settings, default **Off**.
- [ ] **Regular width + Off:** long-page scroll keeps the bar fixed — verified with the address bar at both top and bottom.
- [ ] **Regular width + On:** long-page scroll hides and reveals the bar conventionally.
- [ ] **Compact width:** bar auto-hides on scroll for both toggle states.
- [ ] Switching **Off** while the bar is hidden (regular width) reveals it immediately.
- [ ] Dragging into/out of split view and rotating flips behavior live at the regular↔compact boundary.
- [ ] Setting persists across relaunch.
- [ ] No regression on phones (compact in portrait → behaves as today).
