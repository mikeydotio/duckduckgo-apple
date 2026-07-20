# bee-badge

Composites the native 🐝 emoji onto the bottom-right corner of this fork's app
icons, so a personal build is visually distinguishable from the App Store
DuckDuckGo on the home screen / Dock. See [issue #25](https://github.com/mikeydotio/duckduckgo-apple/issues/25).

## Usage

```sh
scripts/bee-badge/generate.sh
```

Idempotent: the first run snapshots every source PNG into `originals/` (a
pristine, un-badged copy) before touching it. Every run after that re-badges
**from `originals/`**, never from a previously-badged file — so re-running
never double-stamps the bee or drifts from the calibrated size/placement. To
fully reset (e.g. after upstream ships new icon artwork), delete
`scripts/bee-badge/originals/` and re-run.

## How it works

`badge.swift` is a dependency-free Swift CLI (Core Graphics + AppKit — no
external packages) that:

1. Renders `🐝` via the system Apple Color Emoji font at high fidelity, then
   crops tightly to its visible pixels — the drawn *glyph*, not its font
   em-box (which has a lot of built-in whitespace), is what ends up sized to
   `--fraction` of the icon.
2. Determines the icon's visible bounds one of two ways, via `--anchor`:
   - `canvas` — the raw pixel square. Use this when the source PNG is
     edge-to-edge with no baked-in shape, and something *else* (the OS, or
     Icon Composer) applies a mask/shape on top at render time — e.g. iOS's
     rounded-squircle app icon mask.
   - `content` — auto-detects the tight bounding box of non-transparent
     pixels. Use this when the source PNG already bakes in its own shape,
     padding, and drop shadow — e.g. macOS's `.appiconset` icons.
3. Composites the glyph bottom-right within those bounds, inset by
   `--inset-fraction` of the bounds' size.
4. Runs a real post-composite sanity check — diffs the target region's pixels
   before/after and fails loudly if the bee didn't visibly land — rather than
   just trusting that the draw call didn't throw.

`--flatten-alpha` drops the alpha channel entirely (writes an opaque PNG).
Used only for iOS's primary/light app icon, which — unlike its dark/tinted
siblings — ships with no alpha channel; the flag preserves that on rebadge.

`--transparent --canvas <n>` skips loading a background PNG and emits the
badge alone, for layered icon formats (Xcode's Icon Composer `.icon`) where
the bee is added as its own layer rather than composited onto a raster.

## Corner-safety math (why `--inset-fraction 0.08` for iOS)

iOS applies its own rounded-corner ("squircle") mask to the 1024×1024 source
PNG at render time — the file itself is a plain edge-to-edge square. Apple's
icon templates use a corner radius of roughly 22% of the icon's size. With
`--fraction 0.25 --inset-fraction 0.08` on a 1024px canvas, the badge's
outermost corner sits ~146px from the mask's corner-circle center — safely
inside even a conservative 230px+ radius. Verified visually (see the PR) and
by this geometry; if upstream ever changes the icon template's corner radius
materially, re-check by eye after running `generate.sh`.

## Deliberately out of scope

- The 6 user-selectable iOS alternate color icons and their in-app picker
  previews.
- iOS Alpha/Experimental icon sets, and macOS's `Icon - Alpha`.
  `Icon - Alpha.appiconset` already bakes in its own bottom-right "a" badge
  circle in the exact corner the bee would occupy — stacking a second corner
  badge there would clutter/obscure both, and Alpha is the least likely
  config for a personal-fork local build anyway.
- macOS's internal-channel / theme-sync runtime icon overrides
  (`AppIconChanger.swift`) — these replace the Dock icon at runtime for
  specific user states and are out of this change's scope.

If broader coverage is ever wanted, extend the file lists in `generate.sh` —
the tool itself is general-purpose.
