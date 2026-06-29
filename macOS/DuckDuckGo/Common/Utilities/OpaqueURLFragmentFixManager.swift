//
//  OpaqueURLFragmentFixManager.swift
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

import Combine
import FeatureFlags
import os.log
import PrivacyConfig

/// Manages the CFURLCreateAbsoluteURLWithBytes swapper that records the raw byte
/// position of '#' fragment delimiters in opaque NSURL objects at construction time.
///
/// The fix is enabled when the `opaqueURLFragmentFix` privacy-config subfeature is on
/// and is re-evaluated whenever the remote config updates, allowing the fix to be
/// killed remotely without a release.
///
/// Ownership: hold a strong reference for the lifetime of the app (e.g. in AppDelegate).
final class OpaqueURLFragmentFixManager {

    private var cancellable: AnyCancellable?

    init(featureFlagger: FeatureFlagger) {
        applyCurrentState(featureFlagger)

        // Re-evaluate on every remote-config or local-override change.
        cancellable = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.applyCurrentState(featureFlagger)
            }
    }

    private func applyCurrentState(_ featureFlagger: FeatureFlagger) {
        if featureFlagger.isFeatureOn(.opaqueURLFragmentFix) {
            installCFURLSwapper()
            Logger.general.debug("OpaqueURLFragmentFix swapper installed")
        } else {
            uninstallCFURLSwapper()
            Logger.general.debug("OpaqueURLFragmentFix swapper uninstalled")
        }
    }

}
