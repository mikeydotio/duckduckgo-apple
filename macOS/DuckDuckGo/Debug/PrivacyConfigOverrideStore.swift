//
//  PrivacyConfigOverrideStore.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import os.log
import PrivacyConfig

/// Session-only store for globally disabled ContentScope features via remote config override.
/// Disabling a feature patches the live privacy config JSON so the real feature-gate code path is exercised.
/// State resets on every app launch (no persistence).
@MainActor
final class PrivacyConfigOverrideStore {
    static let shared = PrivacyConfigOverrideStore()
    private init() {}

    private(set) var overriddenFeatures: Set<String> = []

    /// Pre-override snapshot of the privacy config JSON.
    /// Must always reflect the state *before* any override was applied.
    /// The `if originalConfigData == nil` guard in `disableFeature` ensures this is
    /// captured exactly once per override session, before the first `reload` call
    /// can mutate `fetchedConfigData`. If this guard were removed, subsequent
    /// `disableFeature` calls would snapshot already-patched data and stack overrides
    /// incorrectly.
    private var originalConfigData: Data?

    func disableFeature(_ key: String, in manager: PrivacyConfigurationManaging) {
        // Capture the pre-override snapshot only once, before any reload mutates config data.
        if originalConfigData == nil {
            originalConfigData = manager.currentConfig
        }
        overriddenFeatures.insert(key)
        applyOverrides(in: manager)
    }

    func enableFeature(_ key: String, in manager: PrivacyConfigurationManaging) {
        overriddenFeatures.remove(key)
        if overriddenFeatures.isEmpty {
            // reload(etag: nil, data: nil) always returns .embedded — no guard needed
            manager.reload(etag: nil, data: nil)
            originalConfigData = nil
        } else {
            applyOverrides(in: manager)
        }
    }

    // MARK: - Private

    private func applyOverrides(in manager: PrivacyConfigurationManaging) {
        guard let original = originalConfigData,
              var json = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any],
              var features = json["features"] as? [String: Any] else { return }

        for key in overriddenFeatures {
            if var feature = features[key] as? [String: Any] {
                feature["state"] = "disabled"
                features[key] = feature
            } else {
                Logger.config.warning("PrivacyConfigOverrideStore: feature key '\(key)' not found in privacy config — override has no effect")
            }
        }
        json["features"] = features

        guard let patchedData = try? JSONSerialization.data(withJSONObject: json) else { return }

        let result = manager.reload(etag: "debug-override", data: patchedData)
        if result == .embeddedFallback {
            // Patched JSON was rejected by the parser — reset to clean state
            overriddenFeatures = []
            originalConfigData = nil
        }
    }
}
