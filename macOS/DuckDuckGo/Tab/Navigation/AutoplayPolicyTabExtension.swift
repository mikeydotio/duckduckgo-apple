//
//  AutoplayPolicyTabExtension.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import FeatureFlags
import Navigation
import PrivacyConfig

final class AutoplayPolicyTabExtension {

    private let autoplayPreferences: AutoplayPreferences
    private let featureFlagger: FeatureFlagger

    init(autoplayPreferences: AutoplayPreferences, featureFlagger: FeatureFlagger) {
        self.autoplayPreferences = autoplayPreferences
        self.featureFlagger = featureFlagger
    }
}

extension AutoplayPolicyTabExtension: NavigationResponder {

    @MainActor
    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        guard featureFlagger.isFeatureOn(.autoplayPolicy) else { return .next }
        preferences.autoplayPolicy = .init(autoplayPreferences.autoplayBlockingMode.mediaTypesRequiringUserAction)
        return .next
    }
}

protocol AutoplayPolicyTabExtensionProtocol: AnyObject, NavigationResponder {}

extension AutoplayPolicyTabExtension: TabExtension, AutoplayPolicyTabExtensionProtocol {
    typealias PublicProtocol = AutoplayPolicyTabExtensionProtocol
    func getPublicProtocol() -> PublicProtocol { self }
}

extension TabExtensions {
    var autoplayPolicy: AutoplayPolicyTabExtensionProtocol? {
        resolve(AutoplayPolicyTabExtension.self)
    }
}
