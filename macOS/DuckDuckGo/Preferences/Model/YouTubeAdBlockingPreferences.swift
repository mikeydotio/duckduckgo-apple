//
//  YouTubeAdBlockingPreferences.swift
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

import AppKit
import Combine
import DuckPlayer
import Foundation
import PixelKit
import PrivacyConfig

protocol YouTubeAdBlockingPreferencesPersistor {
    var youTubeAdBlockingEnabled: Bool { get set }
}

struct YouTubeAdBlockingPreferencesUserDefaultsPersistor: YouTubeAdBlockingPreferencesPersistor {

    @UserDefaultsWrapper(key: .youTubeAdBlockingEnabled, defaultValue: true)
    var youTubeAdBlockingEnabled: Bool
}

final class YouTubeAdBlockingPreferences: ObservableObject {
    private let internalUserDecider: InternalUserDecider
    private let duckPlayerContingencyHandler: DuckPlayerContingencyHandler
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private var youTubeAdBlockingPersistor: YouTubeAdBlockingPreferencesPersistor
    private var duckPlayerPersistor: DuckPlayerPreferencesPersistor

    @Published
    var youTubeAdBlockingEnabled: Bool {
        didSet {
            youTubeAdBlockingPersistor.youTubeAdBlockingEnabled = youTubeAdBlockingEnabled
        }
    }

    @Published
    var duckPlayerMode: DuckPlayerMode {
        didSet {
            duckPlayerPersistor.duckPlayerModeBool = duckPlayerMode.boolValue
        }
    }

    @Published
    var duckPlayerAutoplay: Bool {
        didSet {
            duckPlayerPersistor.duckPlayerAutoplay = duckPlayerAutoplay
            if duckPlayerAutoplay {
                PixelKit.fire(GeneralPixel.duckPlayerAutoplaySettingsOn, doNotEnforcePrefix: true)
            } else {
                PixelKit.fire(GeneralPixel.duckPlayerAutoplaySettingsOff, doNotEnforcePrefix: true)
            }
        }
    }

    @Published
    var duckPlayerOpenInNewTab: Bool {
        didSet {
            duckPlayerPersistor.duckPlayerOpenInNewTab = duckPlayerOpenInNewTab
            if duckPlayerOpenInNewTab {
                PixelKit.fire(GeneralPixel.duckPlayerNewTabSettingsOn, doNotEnforcePrefix: true)
            } else {
                PixelKit.fire(GeneralPixel.duckPlayerNewTabSettingsOff, doNotEnforcePrefix: true)
            }
        }
    }

    var shouldDisplayAutoPlaySettings: Bool {
        privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(DuckPlayerSubfeature.autoplay) || internalUserDecider.isInternalUser
    }

    var isOpenInNewTabSettingsAvailable: Bool {
        privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(DuckPlayerSubfeature.openInNewTab) || internalUserDecider.isInternalUser
    }

    var isNewTabSettingsAvailable: Bool {
        duckPlayerMode != .disabled
    }

    var youtubeOverlayInteracted: Bool {
        didSet {
            duckPlayerPersistor.youtubeOverlayInteracted = youtubeOverlayInteracted
        }
    }

    var youtubeOverlayAnyButtonPressed: Bool {
        didSet {
            duckPlayerPersistor.youtubeOverlayAnyButtonPressed = youtubeOverlayAnyButtonPressed
        }
    }

    var shouldDisplayContingencyMessage: Bool {
        duckPlayerContingencyHandler.shouldDisplayContingencyMessage
    }

    func reset() {
        youtubeOverlayAnyButtonPressed = false
        youtubeOverlayInteracted = false
        duckPlayerMode = .alwaysAsk
        duckPlayerOpenInNewTab = true
        duckPlayerAutoplay = true
    }

    @MainActor
    func openLearnMoreContingencyURL() {
        guard let url = duckPlayerContingencyHandler.learnMoreURL else { return }
        PixelKit.fire(GeneralPixel.duckPlayerContingencyLearnMoreClicked, doNotEnforcePrefix: true)
        Application.appDelegate.windowControllersManager.show(url: url, source: .ui, newTab: true)
    }

    init(youTubeAdBlockingPersistor: YouTubeAdBlockingPreferencesPersistor = YouTubeAdBlockingPreferencesUserDefaultsPersistor(),
         duckPlayerPersistor: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
         privacyConfigurationManager: PrivacyConfigurationManaging = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
         internalUserDecider: InternalUserDecider = NSApp.delegateTyped.internalUserDecider) {
        self.youTubeAdBlockingPersistor = youTubeAdBlockingPersistor
        self.duckPlayerPersistor = duckPlayerPersistor
        youTubeAdBlockingEnabled = youTubeAdBlockingPersistor.youTubeAdBlockingEnabled
        duckPlayerMode = .init(duckPlayerPersistor.duckPlayerModeBool)
        youtubeOverlayInteracted = duckPlayerPersistor.youtubeOverlayInteracted
        youtubeOverlayAnyButtonPressed = duckPlayerPersistor.youtubeOverlayAnyButtonPressed
        duckPlayerAutoplay = duckPlayerPersistor.duckPlayerAutoplay
        duckPlayerOpenInNewTab = duckPlayerPersistor.duckPlayerOpenInNewTab
        self.privacyConfigurationManager = privacyConfigurationManager
        self.internalUserDecider = internalUserDecider
        self.duckPlayerContingencyHandler = DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: privacyConfigurationManager)
    }
}
