//
//  EventHubService.swift
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

import Core
import EventHub
import Foundation
import PrivacyConfig
import UIKit
import WebKit

final class EventHubService {

    let coordinator: EventHubCoordinator

    init(configManager: PrivacyConfigurationManaging) {
        coordinator = EventHubCoordinator(
            configManager: configManager,
            pixelFiring: iOSEventHubPixelFiring(),
            appStateProvider: iOSAppStateProvider(),
            tabIdProvider: iOSTabIdProvider()
        )
    }

    func resume() {
        coordinator.applicationDidBecomeActive()
    }
}

private struct iOSEventHubPixelFiring: EventHubPixelFiring {
    func firePixel(named pixelName: String, parameters: [String: String]) {
        Pixel.fire(pixelNamed: pixelName,
                   withAdditionalParameters: parameters,
                   includedParameters: [.appVersion])
    }
}

private struct iOSAppStateProvider: EventHubAppStateProviding {
    var isAppInForeground: Bool {
        DispatchQueue.main.sync {
            UIApplication.shared.applicationState == .active
        }
    }
}

final class iOSTabIdProvider: EventHubTabIdProviding {

    private var webViewToTabId: NSMapTable<WKWebView, NSString> = .weakToStrongObjects()

    func register(webView: WKWebView, tabId: String) {
        webViewToTabId.setObject(tabId as NSString, forKey: webView)
    }

    func tabId(for webView: WKWebView?) -> String? {
        guard let webView else { return nil }
        return webViewToTabId.object(forKey: webView) as String?
    }
}
