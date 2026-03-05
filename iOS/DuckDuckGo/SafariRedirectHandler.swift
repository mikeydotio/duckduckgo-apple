//
//  SafariRedirectHandler.swift
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

import UIKit
import Core

protocol SafariRedirectHandling: AnyObject {
    /// Whether the given URL was loaded after a suppressed x-safari-https redirect (for breakage reports).
    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool

    /// Called from decidePolicyFor when an x-safari-https URL is encountered.
    /// Returns true if the handler consumed the navigation (caller should .cancel).
    @discardableResult
    func handleRedirect(to url: URL) -> Bool

    /// Full reset including the redirect-detected flag. Called on new top-level navigation.
    func reset()
}

protocol SafariRedirectHandlerDelegate: AnyObject {
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestLoadURL url: URL)
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestOpenExternallyURL url: URL)
    func safariRedirectHandlerDidRequestGoBack(_ handler: SafariRedirectHandling)
    func safariRedirectHandler(_ handler: SafariRedirectHandling, didRequestPresentAlert alert: UIAlertController)
}

final class SafariRedirectHandler: SafariRedirectHandling {

    private enum Constants {
        static let safariRedirectScheme = "x-safari-https"
    }

    /// Hosts that had an x-safari-https redirect suppressed (for breakage reports).
    private var suppressedRedirectHosts: Set<String> = []

    /// The host currently being tracked for alert/loop state.
    private var activeHost: String?
    private var redirectCount: Int = 0
    private var stayEnabled: Bool = false
    private var alertShown: Bool = false

    weak var delegate: SafariRedirectHandlerDelegate?

    func isAfterSuppressedXSafariRedirect(for url: URL) -> Bool {
        guard let host = url.host else { return false }
        return suppressedRedirectHosts.contains(host)
    }

    func handleRedirect(to url: URL) -> Bool {
        guard url.scheme == Constants.safariRedirectScheme else { return false }

        let host = url.host
        if host != activeHost {
            activeHost = host
            redirectCount = 0
            stayEnabled = false
            alertShown = false
        }

        if let host {
            suppressedRedirectHosts.insert(host)
        }

        if !stayEnabled && !alertShown {
            alertShown = true
            showTryOpenAlert(url: url)
            return true
        } else if !stayEnabled && alertShown {
            return handleSubsequentRedirect(url: url)
        } else {
            return handleSubsequentRedirect(url: url)
        }
    }

    func reset() {
        activeHost = nil
        redirectCount = 0
        stayEnabled = false
        alertShown = false
        suppressedRedirectHosts.removeAll()
    }

    // MARK: - Private

    private func handleSubsequentRedirect(url: URL) -> Bool {
        redirectCount += 1
        if redirectCount > 2 {
            Pixel.fire(pixel: .webViewExternalSchemeNavigationXSafariHTTPSLoopDetected)
            showLoopAlert(url: url)
        } else {
            convertAndLoad(url: url)
        }
        return true
    }

    private func convertAndLoad(url: URL) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        if let httpsURL = components?.url {
            delegate?.safariRedirectHandler(self, didRequestLoadURL: httpsURL)
        }
    }

    private func showTryOpenAlert(url: URL) {
        let alert = UIAlertController(
            title: UserText.xSafariHTTPSTryOpenTitle,
            message: UserText.xSafariHTTPSTryOpenMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSStayInDDG, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            Pixel.fire(pixel: .webViewExternalSchemeNavigationXSafariHTTPSStay)
            self.stayEnabled = true
            self.redirectCount = 0
            self.convertAndLoad(url: url)
        }))

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSOpenInSafari, style: .default, handler: { [weak self] _ in
            guard let self else { return }
            Pixel.fire(pixel: .webViewExternalSchemeNavigationXSafariHTTPSOpenInSafari)
            self.alertShown = false
            self.delegate?.safariRedirectHandler(self, didRequestOpenExternallyURL: url)
        }))

        delegate?.safariRedirectHandler(self, didRequestPresentAlert: alert)
    }

    private func showLoopAlert(url: URL) {
        let alert = UIAlertController(
            title: UserText.xSafariHTTPSLoopTitle,
            message: UserText.xSafariHTTPSLoopMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSGoBack, style: .cancel, handler: { [weak self] _ in
            guard let self else { return }
            self.stayEnabled = false
            self.alertShown = false
            self.redirectCount = 0
            self.delegate?.safariRedirectHandlerDidRequestGoBack(self)
        }))

        alert.addAction(UIAlertAction(title: UserText.xSafariHTTPSOpenInSafari, style: .default, handler: { [weak self] _ in
            guard let self else { return }
            Pixel.fire(pixel: .webViewExternalSchemeNavigationXSafariHTTPSLoopOpenInSafari)
            self.alertShown = false
            self.delegate?.safariRedirectHandler(self, didRequestOpenExternallyURL: url)
        }))

        delegate?.safariRedirectHandler(self, didRequestPresentAlert: alert)
    }
}
