#!/usr/bin/env bash
# Build metrics_aggregator Rust crate as a macOS xcframework (arm64 + x86_64, or current arch only).
# Output: dist/MetricsAggregatorRust.xcframework
# Run from repo root or from metrics_aggregator_rust/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$CRATE_DIR/dist"
INCLUDE_DIR="$CRATE_DIR/include"

cd "$CRATE_DIR"

# Ensure targets are installed (best-effort)
command -v rustup >/dev/null 2>&1 && rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

# Build for current architecture first (always needed)
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    CURRENT_TARGET="aarch64-apple-darwin"
else
    CURRENT_TARGET="x86_64-apple-darwin"
fi

cargo build --release --target "$CURRENT_TARGET"

# Try to build the other architecture; if target not installed, build single-arch xcframework
OTHER_TARGET=""
if [[ "$CURRENT_TARGET" == "aarch64-apple-darwin" ]]; then
    OTHER_TARGET="x86_64-apple-darwin"
else
    OTHER_TARGET="aarch64-apple-darwin"
fi

if cargo build --release --target "$OTHER_TARGET" 2>/dev/null; then
    BUILD_BOTH=1
else
    BUILD_BOTH=0
fi

rm -rf "$DIST_DIR"
# Use a subdirectory for headers so we don't conflict with other xcframeworks (e.g. Clibsodium) that emit include/module.modulemap
HEADERS_SUBDIR="MetricsAggregatorRust"
mkdir -p "$DIST_DIR/macos-arm64/Headers/$HEADERS_SUBDIR"
mkdir -p "$DIST_DIR/macos-x86_64/Headers/$HEADERS_SUBDIR"

# Copy dylibs and set install name so the app loads from its bundle, not the Cargo build path
copy_dylib() {
    local src="$1"
    local dest="$2"
    cp "$src" "$dest" 2>/dev/null || return 1
    install_name_tool -id "@rpath/libmetrics_aggregator.dylib" "$dest"
}
copy_dylib "$CRATE_DIR/target/aarch64-apple-darwin/release/libmetrics_aggregator.dylib" "$DIST_DIR/macos-arm64/libmetrics_aggregator.dylib" || true
copy_dylib "$CRATE_DIR/target/x86_64-apple-darwin/release/libmetrics_aggregator.dylib" "$DIST_DIR/macos-x86_64/libmetrics_aggregator.dylib" || true
cp "$INCLUDE_DIR/MetricsAggregatorRust.h" "$INCLUDE_DIR/module.modulemap" "$DIST_DIR/macos-arm64/Headers/$HEADERS_SUBDIR/"
cp "$INCLUDE_DIR/MetricsAggregatorRust.h" "$INCLUDE_DIR/module.modulemap" "$DIST_DIR/macos-x86_64/Headers/$HEADERS_SUBDIR/"

# Create xcframework (one or two slices)
if [[ "$BUILD_BOTH" -eq 1 ]]; then
    xcodebuild -create-xcframework \
        -library "$DIST_DIR/macos-arm64/libmetrics_aggregator.dylib" \
        -headers "$DIST_DIR/macos-arm64/Headers" \
        -library "$DIST_DIR/macos-x86_64/libmetrics_aggregator.dylib" \
        -headers "$DIST_DIR/macos-x86_64/Headers" \
        -output "$DIST_DIR/MetricsAggregatorRust.xcframework"
else
    SLICE_DIR="$DIST_DIR/macos-${ARCH}"
    mkdir -p "$SLICE_DIR/Headers/$HEADERS_SUBDIR"
    copy_dylib "$CRATE_DIR/target/$CURRENT_TARGET/release/libmetrics_aggregator.dylib" "$SLICE_DIR/libmetrics_aggregator.dylib"
    cp "$INCLUDE_DIR/MetricsAggregatorRust.h" "$INCLUDE_DIR/module.modulemap" "$SLICE_DIR/Headers/$HEADERS_SUBDIR/"
    xcodebuild -create-xcframework \
        -library "$SLICE_DIR/libmetrics_aggregator.dylib" \
        -headers "$SLICE_DIR/Headers" \
        -output "$DIST_DIR/MetricsAggregatorRust.xcframework"
    rm -rf "$SLICE_DIR"
fi

# Remove intermediate slices
rm -rf "$DIST_DIR/macos-arm64" "$DIST_DIR/macos-x86_64"

echo "Built $DIST_DIR/MetricsAggregatorRust.xcframework"
