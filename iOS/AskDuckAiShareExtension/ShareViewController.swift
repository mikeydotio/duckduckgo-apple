//
//  ShareViewController.swift
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

/// Action extension that hands a shared image to Duck.ai.
///
/// Appears in the share sheet's action row as "Ask Duck.ai". It writes the image bytes into the
/// shared App Group container, then opens the host app with `ddgOpenAIChat://?image=<token>` so the
/// app can attach the image to a new Duck.ai prompt. Self-contained (no `Core` dependency); the
/// values here must match `SharedAIChatImageStore` in the app.
final class ShareViewController: UIViewController {

    private enum Constants {
        static let groupIdPrefixInfoKey = "DuckDuckGoGroupIdentifierPrefix"
        static let appConfigurationGroupSuffix = ".app-configuration"
        static let sharedImagesDirectory = "AskDuckAiSharedImages"
        static let imageTypeIdentifier = "public.image"
        static let deepLinkScheme = "ddgOpenAIChat"
        static let openURLSelector = "openURL:"
    }

    /// The shared App Group, resolved from the build-injected group-id prefix so it matches the app
    /// (and the current build flavor) without linking `Core`.
    private var appGroupIdentifier: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: Constants.groupIdPrefixInfoKey) as? String else {
            return nil
        }
        return prefix + Constants.appConfigurationGroupSuffix
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let provider = imageItemProvider() else {
            done()
            return
        }
        loadImage(from: provider)
    }

    private func imageItemProvider() -> NSItemProvider? {
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            if let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(Constants.imageTypeIdentifier) }) {
                return provider
            }
        }
        return nil
    }

    private func loadImage(from provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: Constants.imageTypeIdentifier) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let token = self.storeImageData(data) {
                    self.openApp(imageToken: token)
                }
                self.done()
            }
        }
    }

    private func storeImageData(_ data: Data) -> String? {
        guard let appGroupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = container.appendingPathComponent(Constants.sharedImagesDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let token = UUID().uuidString
        do {
            try data.write(to: directory.appendingPathComponent(token), options: .atomic)
            return token
        } catch {
            return nil
        }
    }

    private func openApp(imageToken: String) {
        guard let url = URL(string: "\(Constants.deepLinkScheme)://?image=\(imageToken)&source=shareSheet") else {
            return
        }
        let selector = sel_registerName(Constants.openURLSelector)
        var responder = self as UIResponder?
        while let current = responder {
            if #available(iOS 18.0, *) {
                if let application = current as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    break
                }
            } else if current.responds(to: selector) {
                _ = current.perform(selector, with: url, with: {})
                break
            }
            responder = current.next
        }
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
