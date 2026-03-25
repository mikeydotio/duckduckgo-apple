//
//  AIChatViewModel.swift
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
//

#if os(iOS)
import WebKit
import Combine
import os.log
import DuckAILocalServerAPI

protocol AIChatViewModeling {
    /// The URL to be loaded in the AI Chat View Controller's web view.
    var aiChatURL: URL { get }

    /// The configuration settings for the web view used in the AI Chat.
    /// This configuration can include preferences such as data storage
    var webViewConfiguration: WKWebViewConfiguration { get }

    /// Handler for decide policy requests inside the AI Chat view
    var requestAuthHandler: AIChatRequestAuthorizationHandling { get }

    /// Forward function from AIChatRequestAuthorizationHandling
    @MainActor
    func shouldAllowRequestWithNavigationAction(_ navigationAction: WKNavigationAction) -> Bool

    /// Sets inspectable property in the webView
    var inspectableWebView: Bool { get }

    /// Path for AI Chat downloads, like exported chat
    var downloadsPath: URL { get }

    /// User Agent to be used on AI Chat
    var userAgent: String { get }

    /// Port of the local server, or 0 if not running
    var localServerPort: UInt16 { get }
}

final class AIChatViewModel: AIChatViewModeling {
    private let settings: AIChatSettingsProvider
    private let userAgentManager: AIChatUserAgentProviding
    private let localServer: (any DuckAILocalServer)?
    let webViewConfiguration: WKWebViewConfiguration
    let requestAuthHandler: AIChatRequestAuthorizationHandling
    let inspectableWebView: Bool
    let downloadsPath: URL
    private var fetchBridgeRetainer: AnyObject?

    init(webViewConfiguration: WKWebViewConfiguration,
         settings: AIChatSettingsProvider,
         requestAuthHandler: AIChatRequestAuthorizationHandling,
         inspectableWebView: Bool,
         downloadsPath: URL,
         userAgentManager: AIChatUserAgentProviding,
         localServer: (any DuckAILocalServer)? = nil) {
        self.webViewConfiguration = webViewConfiguration
        self.settings = settings
        self.requestAuthHandler = requestAuthHandler
        self.inspectableWebView = inspectableWebView
        self.downloadsPath = downloadsPath
        self.userAgentManager = userAgentManager
        self.localServer = localServer

        if let localServer, localServer.port > 0 {
            fetchBridgeRetainer = DuckAILocalServerScriptInstaller.install(
                on: webViewConfiguration.userContentController,
                port: localServer.port
            )
        }
    }

    var aiChatURL: URL {
        settings.aiChatURL
    }

    @MainActor
    func shouldAllowRequestWithNavigationAction(_ navigationAction: WKNavigationAction) -> Bool {
        requestAuthHandler.shouldAllowRequestWithNavigationAction(navigationAction)
    }

    var userAgent: String {
        userAgentManager.userAgent(url: aiChatURL)
    }

    var localServerPort: UInt16 {
        localServer?.port ?? 0
    }
}
#endif
