//
//  WebExtensionManager+iOS.swift
//  DuckDuckGo
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

import UIKit
import WebExtensions
import WebKit
import Core
import PrivacyConfig

// MARK: - Factory

@available(iOS 18.4, *)
public enum WebExtensionManagerFactory {

    @MainActor
    static func makeManager(mainViewController: MainViewController) -> WebExtensionManager {
        // Get privacy config as raw JSON string
        let privacyConfigString = getPrivacyConfigString()
        let currentConfig = ContentBlocking.shared.privacyConfigurationManager.currentConfig
        let privacyConfigData = try? PrivacyConfigurationData(data: currentConfig)

        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: WebExtensionWindowTabProvider(mainViewController: mainViewController),
            storageProvider: WebExtensionStorageProvider(),
            privacyConfigString: privacyConfigString,
            // FIXME: make sure it's updated when the privacy config changes
            privacyConfig: ContentBlocking.shared.privacyConfigurationManager.privacyConfig,
            privacyConfigData: privacyConfigData
        )

        return manager
    }

    /// Gets the raw privacy configuration JSON string.
    @MainActor
    private static func getPrivacyConfigString() -> String? {
        let privacyConfigData = ContentBlocking.shared.privacyConfigurationManager.currentConfig
        return String(data: privacyConfigData, encoding: .utf8)
    }
}
