//
//  PrivacyPassNavigationResponder.swift
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

import BrowserServicesKit
import Combine
import Foundation
import Navigation
import os.log
import PrivacyConfig
import WebKit

/// Handles Privacy Pass 401 challenges as a `NavigationResponder`.
///
/// Detects `WWW-Authenticate: PrivateToken` on 401 responses for GET main-frame
/// navigations and performs the ACT issuance/spend flow, then replays the
/// navigation with an `Authorization` header.
final class PrivacyPassNavigationResponder: NavigationResponder {

    private let challengeHandler: PrivacyPassChallengeHandler
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private weak var webView: WKWebView?

    init(challengeHandler: PrivacyPassChallengeHandler,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         webViewFuture: Future<WKWebView, Never>) {
        self.challengeHandler = challengeHandler
        self.privacyConfigurationManager = privacyConfigurationManager

        // Resolve the webView when it becomes available
        var cancellable: AnyCancellable?
        cancellable = webViewFuture.sink { [weak self] webView in
            self?.webView = webView
            cancellable?.cancel()
        }
    }

    @MainActor
    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        guard privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .privacyPass),
              let httpResponse = navigationResponse.httpResponse,
              navigationResponse.mainFrameNavigation?.navigationAction.request.httpMethod == "GET",
              challengeHandler.isPrivacyPassChallenge(httpResponse),
              let originalURL = navigationResponse.url as URL? else {
            return .next
        }

        // Cancel the 401 response and asynchronously retry with authorization
        Task { @MainActor [weak self] in
            guard let self, let webView else { return }
            do {
                try await challengeHandler.handleChallengeAndRetry(
                    response: httpResponse,
                    originalURL: originalURL,
                    webView: webView)
            } catch {
                Logger.privacyPass.error("Privacy Pass challenge handling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return .cancel
    }
}
