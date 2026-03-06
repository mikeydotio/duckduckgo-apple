//
//  AutoplayTabExtension.swift
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
import Navigation
import WebKit

@MainActor
final class AutoplayTabExtension {

    private let autoplayPreferences: AutoplayPreferences
    private weak var webView: WKWebView?
    /// Tracks the mode that has been applied to the WebView, to avoid unnecessary reloads.
    /// Exposed as `internal` (and `@Published`) for unit testing.
    @Published private(set) var configuredMode: AutoplayBlockingMode
    var currentURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var preferenceCancellables = Set<AnyCancellable>()

    init(autoplayPreferences: AutoplayPreferences,
         webViewPublisher: some Publisher<WKWebView, Never>) {
        self.autoplayPreferences = autoplayPreferences
        self.configuredMode = autoplayPreferences.autoplayBlockingMode
        webViewPublisher
            .sink { [weak self] wv in self?.webViewDidAppear(wv) }
            .store(in: &cancellables)
    }

    func webViewDidAppear(_ webView: WKWebView) {
        self.webView = webView
        preferenceCancellables.removeAll()
        subscribeToPreferenceChanges()
    }

    private func subscribeToPreferenceChanges() {
        autoplayPreferences.$autoplayBlockingMode
            .combineLatest(autoplayPreferences.$exceptions)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self, let url = self.currentURL else { return }
                // A page is already displayed — update config and reload so media respects the new policy.
                self.updateConfig(for: url, reload: true)
            }
            .store(in: &preferenceCancellables)
    }

    /// Updates `webView.configuration.mediaTypesRequiringUserActionForPlayback` for the given URL.
    /// Pass `reload: true` only when a page is already displayed and needs to re-evaluate media policy.
    /// Pass `reload: false` (from `didStart`) to configure before page load — no reload needed.
    /// Exposed as `internal` for unit testing.
    func updateConfig(for url: URL, reload: Bool) {
        guard let webView else { return }
        let effective = autoplayPreferences.effectiveMode(for: url)
        guard effective != configuredMode else { return }
        configuredMode = effective
        webView.configuration.mediaTypesRequiringUserActionForPlayback = effective.mediaTypesRequiringUserAction
        if reload {
            webView.reload()
        }
    }
}

// MARK: - NavigationResponder

extension AutoplayTabExtension: NavigationResponder {

    func didStart(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame else { return }
        let url = navigation.url
        currentURL = url
        // Navigation is in progress — update config now so media policy is correct when the page loads.
        // Do NOT reload: calling reload() during an active navigation cancels it and reloads the previous page.
        updateConfig(for: url, reload: false)
    }
}

// MARK: - TabExtension

// Must inherit NavigationResponder so `TabExtensions.autoplay` can be passed to
// `DistributedNavigationDelegate.setResponders` in `Tab+Navigation.swift`.
protocol AutoplayExtensionProtocol: AnyObject, NavigationResponder {}

extension AutoplayTabExtension: TabExtension, AutoplayExtensionProtocol {
    func getPublicProtocol() -> AutoplayExtensionProtocol { self }
}

extension TabExtensions {
    var autoplay: AutoplayExtensionProtocol? {
        resolve(AutoplayTabExtension.self)
    }
}
