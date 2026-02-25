# metrics_aggregator (Rust)

SQLite-backed metrics aggregator for pixel emission. Exposes a C FFI for use from the Swift MetricsAggregatorMac package.

## Build xcframework (macOS)

Before building the Swift package that depends on this crate, you must produce the xcframework:

```bash
cd macOS/metrics_aggregator_rust
./scripts/build-macos.sh
```

Requires Rust (e.g. `rustup`) and Xcode. Output: `dist/MetricsAggregatorRust.xcframework`.

## Regenerating the C header

If you change the FFI in `src/lib.rs`, regenerate the header with cbindgen:

```bash
cbindgen --config cbindgen.toml --crate metrics_aggregator --output include/MetricsAggregatorRust.h
```

Then run `./scripts/build-macos.sh` again.
