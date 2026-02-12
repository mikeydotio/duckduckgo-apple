# Feature Flag Guide

Each app declares a `FeatureFlag` enum conforming to [`FeatureFlagDescribing`](./FeatureFlagger.swift). Each case implements `defaultValue`, `source`, `supportsLocalOverriding`, and `cohortType` -- see the protocol definition and existing flags for the pattern:

- iOS: [`iOS/Core/FeatureFlag.swift`](../../../../../iOS/Core/FeatureFlag.swift)
- macOS: [`macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`](../../../../../macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift)
- Sub-feature enums: [`PrivacyFeature.swift`](../Features/PrivacyFeature.swift)

For the cross-platform overview of the remote config system, see the [Feature Flagging Guide](https://github.com/duckduckgo/privacy-configuration/blob/main/docs/feature-flagging-guide.md).

## Choosing a Default Value

**`false` (opt-in)** -- for new or experimental features. The feature stays off unless remote config enables it.

**`true` (failsafe / kill-switch)** -- for stable, already-shipping features. The feature is on by default; you can disable it remotely if problems arise. See [Using failsafe feature flags](https://app.asana.com/0/0/1209498782498498/f).

**Changing a default on a shipped feature**: if flipping from `false` to `true`, set `minSupportedVersion` in the remote config to the version that includes the change. Otherwise older versions without the finished implementation will activate the feature when they can't reach the config.

## Footguns

**Always use `.remoteReleasable(.subfeature(...))`** -- mapping to a parent feature via `.remoteReleasable(.feature(...))` silently loses rollout, target, and cohort support. This has caused incidents. If no sub-feature exists, add one to [`PrivacyFeature.swift`](../Features/PrivacyFeature.swift) under the appropriate parent (`iOSBrowserConfigSubfeature`, `MacOSBrowserConfigSubfeature`, or a domain-specific parent like `AIChatSubfeature`).

**Don't forget `supportsLocalOverriding`** -- most flags should return `true` so internal users can test both states via the debug menu. Only use `false` for production pixels/metrics or security-critical paths.

## Adding a New Flag

1. Create an Asana task in the **Apple Feature Flags Registry**.
2. Add the `case` to the `FeatureFlag` enum (iOS and/or macOS) with an Asana link comment.
3. Set `defaultValue`, `source`, `supportsLocalOverriding` -- follow the patterns in the existing switch statements.
4. Add the sub-feature case to [`PrivacyFeature.swift`](../Features/PrivacyFeature.swift) if using a remote source.
5. If macOS, consider adding the flag to a category in `FeatureFlagCategory.swift`.
6. Coordinate with the [privacy-configuration](https://github.com/duckduckgo/privacy-configuration) repo to ensure the sub-feature exists in the config.
7. Test both states via the debug menu.

## Related Documentation

- [Feature Flagging Guide (cross-platform)](https://github.com/duckduckgo/privacy-configuration/blob/main/docs/feature-flagging-guide.md)
- [Using failsafe feature flags](https://app.asana.com/0/0/1209498782498498/f)
