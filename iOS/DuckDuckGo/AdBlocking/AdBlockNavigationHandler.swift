//
//  AdBlockNavigationHandler.swift
//  DuckDuckGo
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

import Foundation
import BrowserServicesKit
import PrivacyConfig
import DuckPlayer

protocol AdBlockNavigationHandling {

    /// Handles a URL change, triggering the ad-block animation if appropriate.
    ///
    /// - Parameters:
    ///   - previousURL: The URL before the change.
    ///   - newURL: The URL after the change.
    func handleURLChange(previousURL: URL?, newURL: URL?)

    /// Resets tracked state so the animation can be re-triggered for the current video.
    func handleReload()
}

final class AdBlockNavigationHandler: AdBlockNavigationHandling {

    private let featureFlagger: FeatureFlagger
    private let onShouldShowAdBlockAnimation: () -> Void
    private var lastAnimatedVideoID: String?

    init(featureFlagger: FeatureFlagger, onShouldShowAdBlockAnimation: @escaping () -> Void) {
        self.featureFlagger = featureFlagger
        self.onShouldShowAdBlockAnimation = onShouldShowAdBlockAnimation
    }

    func handleURLChange(previousURL: URL?, newURL: URL?) {
        guard featureFlagger.isFeatureOn(.adBlockingExtension) else { return }

        guard let newURL, newURL.isPlayableYoutubeVideoContent else { return }

        guard let newVideoID = newURL.youtubeVideoID else { return }

        let isNewVideo = newVideoID != previousURL?.youtubeVideoID
        let hasNotAnimatedForCurrentVideo = lastAnimatedVideoID != newVideoID

        if isNewVideo || hasNotAnimatedForCurrentVideo {
            lastAnimatedVideoID = newVideoID
            onShouldShowAdBlockAnimation()
            Logger.general.debug("---- AdBlockNavigationHandler animation!")
        }
    }

    func handleReload() {
        lastAnimatedVideoID = nil
    }
}
