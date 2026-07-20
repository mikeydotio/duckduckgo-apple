#!/bin/bash
#
#  generate.sh
#  bee-badge
#
#  Composites the 🐝 bee badge onto every app icon this fork's default build
#  configurations render, so a build of this fork is visually distinguishable
#  from the App Store DuckDuckGo (see GitHub issue #25).
#
#  Idempotent: the first run snapshots each source PNG into originals/ (a
#  pristine, un-badged copy) before touching it; every run after that always
#  re-badges FROM originals/, so re-running this script never double-badges
#  or drifts from the calibrated placement. To fully reset, delete
#  scripts/bee-badge/originals/ and re-run.
#
#  Deliberately out of scope (see README.md for the reasoning):
#    - The 6 user-selectable iOS alternate color icons.
#    - iOS Alpha/Experimental icon sets.
#    - macOS "Icon - Alpha" — it already bakes in its own bottom-right "a"
#      badge circle in the exact corner the bee would occupy; stacking a
#      second corner badge there would clutter/obscure both, and Alpha is
#      the least likely config for local personal-fork builds.
#
#  Copyright © 2026 Mikey Ward. Licensed under the Apache License, Version 2.0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BADGE_SWIFT="$SCRIPT_DIR/badge.swift"
ORIGINALS_DIR="$SCRIPT_DIR/originals"

# badge_file <repo-relative-path> <anchor> <fraction> <inset-fraction> <flatten: yes|no>
#
# Snapshots <repo-relative-path> into originals/ on first encounter (if not
# already present), then always regenerates the live file by badging FROM
# that pristine snapshot — never from a previously-badged copy.
badge_file() {
  local rel_path="$1" anchor="$2" fraction="$3" inset="$4" flatten="$5"
  local live_path="$REPO_ROOT/$rel_path"
  local original_path="$ORIGINALS_DIR/$rel_path"

  if [ ! -f "$original_path" ]; then
    mkdir -p "$(dirname "$original_path")"
    cp "$live_path" "$original_path"
    echo "bee-badge: snapshotted originals/$rel_path"
  fi

  local flags=(--anchor "$anchor" --fraction "$fraction" --inset-fraction "$inset")
  if [ "$flatten" = "yes" ]; then
    flags+=(--flatten-alpha)
  fi

  swift "$BADGE_SWIFT" --input "$original_path" --output "$live_path" "${flags[@]}"
}

# badge_appiconset <appiconset-dir-name-under-Assets.xcassets> <anchor> <fraction> <inset> <file...>
badge_appiconset() {
  local platform_dir="$1" appiconset="$2" anchor="$3" fraction="$4" inset="$5"
  shift 5
  local name
  for name in "$@"; do
    badge_file "$platform_dir/Assets.xcassets/$appiconset.appiconset/$name.png" "$anchor" "$fraction" "$inset" no
  done
}

echo "== iOS: AppIcon.appiconset (Debug + Release) =="
# anchor=canvas: the source PNGs are edge-to-edge with no baked-in shape —
# iOS applies its rounded-squircle mask at render time, outside this file.
# inset-fraction=0.08 keeps the badge clear of that mask (verified against
# Apple's ~22% corner-radius convention; see README.md).
badge_file "iOS/DuckDuckGo/Assets.xcassets/AppIcon.appiconset/Icon-Light-Default-1024x1024.png" canvas 0.25 0.08 yes
badge_file "iOS/DuckDuckGo/Assets.xcassets/AppIcon.appiconset/Icon-Dark-Default-1024x1024.png" canvas 0.25 0.08 no
badge_file "iOS/DuckDuckGo/Assets.xcassets/AppIcon.appiconset/Icon-Tinted-1024x1024.png" canvas 0.25 0.08 no

echo "== macOS: AppIcon.appiconset (Release / DeveloperID) =="
# anchor=content: these PNGs already bake in the rounded square + drop
# shadow with real transparent padding, so auto-detecting the visible
# content's bounding box anchors the badge to the icon's actual edge.
appicon_files=(Browser-16 "Browser-16@2x" Browser-32 "Browser-32@2x" Browser-128 "Browser-128@2x" Browser-256 "Browser-256@2x" Browser-512 "Browser-512@2x")
badge_appiconset macOS/DuckDuckGo AppIcon content 0.25 0.04 "${appicon_files[@]}"

echo "== macOS: Icon - Debug.appiconset =="
debug_files=(Icon-Debug-16 Icon-Debug-32 "Icon-Debug-32 1" Icon-Debug-64 Icon-Debug-128 Icon-Debug-256 "Icon-Debug-256 1" Icon-Debug-512 "Icon-Debug-512 1" Icon-Debug-1024)
badge_appiconset macOS/DuckDuckGo "Icon - Debug" content 0.25 0.04 "${debug_files[@]}"

echo "== macOS: Icon - Review.appiconset =="
review_files=(Icon-Review-16 "Icon-Review-32 1" Icon-Review-32 Icon-Review-64 Icon-Review-128 "Icon-Review-256 1" Icon-Review-256 "Icon-Review-256@2x" Icon-Review-512 Icon-Review-1024)
badge_appiconset macOS/DuckDuckGo "Icon - Review" content 0.25 0.04 "${review_files[@]}"

echo "== macOS: Icon Composer AppIcon.icon overlay layer =="
# The Icon Composer bundle has no "original" to snapshot — this asset is
# newly created by this script, and icon.json (edited separately, once,
# by hand) references it as an added top layer. Regenerated unconditionally
# each run since it has no upstream artwork to badge onto (transparent).
icon_composer_bee="$REPO_ROOT/macOS/DuckDuckGo/AppIcon.icon/Assets/Bee-Overlay-1024.png"
swift "$BADGE_SWIFT" --transparent --canvas 1024 --output "$icon_composer_bee" \
  --anchor canvas --fraction 0.25 --inset-fraction 0.08
echo "bee-badge: wrote $icon_composer_bee"

echo "bee-badge: done."
