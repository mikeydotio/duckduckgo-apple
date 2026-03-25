//
//  AIChatTabExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Navigation
import Foundation
import Combine
import WebKit
import AIChat
import BrowserServicesKit
import DuckAILocalServerAPI

protocol AIChatUserScriptProvider {
    var aiChatUserScript: AIChatUserScript? { get }
}
extension UserScripts: AIChatUserScriptProvider {}

final class AIChatTabExtension {

    private var cancellables = Set<AnyCancellable>()
    private var userScriptCancellables = Set<AnyCancellable>()
    private let isLoadedInSidebar: Bool
    private weak var webView: WKWebView?
    private let featureDiscovery: FeatureDiscovery
    private let localServerProvider: () -> (any DuckAILocalServer)?
    private var migrationDone = false
    private var fetchBridgeRetainer: AnyObject?
    private var fetchBridgeJavaScript: String?

    private(set) weak var aiChatUserScript: AIChatUserScript? {
        didSet {
            subscribeToUserScript()
        }
    }

    init(scriptsPublisher: some Publisher<some AIChatUserScriptProvider, Never>,
         webViewPublisher: some Publisher<WKWebView, Never>,
         isLoadedInSidebar: Bool,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
         localServerProvider: @escaping () -> (any DuckAILocalServer)? = { nil }) {
        self.isLoadedInSidebar = isLoadedInSidebar
        self.featureDiscovery = featureDiscovery
        self.localServerProvider = localServerProvider
        pageContextRequestedPublisher = pageContextRequestedSubject.eraseToAnyPublisher()
        pageContextConsumedPublisher = pageContextConsumedSubject.eraseToAnyPublisher()
        pageContextRemovedPublisher = pageContextRemovedSubject.eraseToAnyPublisher()
        chatRestorationDataPublisher = chatRestorationDataSubject.eraseToAnyPublisher()

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
            self?.aiChatUserScript?.webView = webView
            self?.registerFetchBridgeIfNeeded(on: webView)
        }.store(in: &cancellables)

        scriptsPublisher.sink { [weak self] scripts in
            Task { @MainActor in
                self?.aiChatUserScript = scripts.aiChatUserScript
                self?.aiChatUserScript?.webView = self?.webView

                // Pass the handoff payload in case it was provided before the user script was loaded
                if let payload = self?.temporaryAIChatNativeHandoffData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
                    self?.temporaryAIChatNativeHandoffData = nil
                }

                if let data = self?.temporaryAIChatRestorationData {
                    self?.aiChatUserScript?.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
                    self?.temporaryAIChatRestorationData = nil
                }

                if let prompt = self?.temporaryAIChatNativePrompt {
                    self?.aiChatUserScript?.handler.submitAIChatNativePrompt(prompt)
                    self?.temporaryAIChatNativePrompt = nil
                }

                if let pageContext = self?.temporaryPageContext {
                    /// See the comment in `self.submitAIChatPageContext` for the explanation of why we're calling user script twice.
                    self?.aiChatUserScript?.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
                    self?.aiChatUserScript?.handler.submitAIChatPageContext(pageContext)
                    self?.temporaryPageContext = nil
                }
            }
        }.store(in: &cancellables)
    }

    private func subscribeToUserScript() {
        userScriptCancellables.removeAll()
        guard let aiChatUserScript else {
            return
        }

        aiChatUserScript.handler.pageContextRequestedPublisher
            .sink { [weak self] _ in
                self?.pageContextRequestedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.pageContextConsumedPublisher
            .sink { [weak self] _ in
                self?.pageContextConsumedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.pageContextRemovedPublisher
            .sink { [weak self] _ in
                self?.pageContextRemovedSubject.send()
            }
            .store(in: &userScriptCancellables)

        aiChatUserScript.handler.chatRestorationDataPublisher
            .sink { [weak self] data in
                self?.chatRestorationDataSubject.send(data)
            }
            .store(in: &userScriptCancellables)
    }

    private let pageContextRequestedSubject = PassthroughSubject<Void, Never>()
    let pageContextRequestedPublisher: AnyPublisher<Void, Never>

    private let pageContextConsumedSubject = PassthroughSubject<Void, Never>()
    let pageContextConsumedPublisher: AnyPublisher<Void, Never>

    private let pageContextRemovedSubject = PassthroughSubject<Void, Never>()
    let pageContextRemovedPublisher: AnyPublisher<Void, Never>

    private let chatRestorationDataSubject = PassthroughSubject<AIChatRestorationData?, Never>()
    let chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never>

    private var temporaryAIChatNativeHandoffData: AIChatPayload?
    func setAIChatNativeHandoffData(payload: AIChatPayload) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativeHandoffData = payload
            return
        }

        aiChatUserScript.handler.messageHandling.setData(payload, forMessageType: .nativeHandoffData)
    }

    private var temporaryAIChatRestorationData: AIChatRestorationData?
    func setAIChatRestorationData(_ data: AIChatRestorationData?) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatRestorationData = data
            return
        }

        aiChatUserScript.handler.messageHandling.setData(data, forMessageType: .chatRestorationData)
    }

    private var temporaryAIChatNativePrompt: AIChatNativePrompt?
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt) {
        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryAIChatNativePrompt = prompt
            return
        }

        aiChatUserScript.handler.submitAIChatNativePrompt(prompt)
    }

    private var temporaryPageContext: AIChatPageContextData?
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?) {
        // Page Context functionality is only for the sidebar.
        guard isLoadedInSidebar else {
            return
        }

        guard let aiChatUserScript else {
            // User script not yet loaded, store the payload and set when ready
            temporaryPageContext = pageContext
            return
        }

        ///
        /// We're both making the data available for `getAIChatPageContext` (by storing it in the page context handler)
        /// and calling `submitAIChatPageContext`, because when sidebar is just presented, it's not ready to receive
        /// `submitAIChatPageContext` and will call `getAIChatPageContext` at a later time (when fully initialized).
        /// After that it will exclusively use `submitAIChatPageContext`.
        ///
        /// This can be optimized later to only call one function, depending on whether `getAIChatPageContext`
        /// was received by this user script.
        ///
        aiChatUserScript.handler.messageHandling.setData(pageContext, forMessageType: .pageContext)
        aiChatUserScript.handler.submitAIChatPageContext(pageContext)
    }
}

extension AIChatTabExtension: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        // Only handle sidebar, user-initiated, cross-document navigations; otherwise let them proceed normally
        guard isLoadedInSidebar,
              !navigationAction.navigationType.isSameDocumentNavigation,
              navigationAction.isUserInitiated
        else {
            return .next
        }

        // Allow-list: also let certain hosts navigate inside the sidebar (e.g., duck.ai)
        if navigationAction.url.isStandaloneDuckAIURL {
            return .next
        }

        // For all other hosts, open in a new tab and cancel sidebar navigation
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else {
            return .next
        }

        let tabCollectionViewModel = parentWindowController.mainViewController.tabCollectionViewModel
        tabCollectionViewModel.insertOrAppendNewTab(.url(navigationAction.url, source: .link))
        return .cancel
    }

    func navigationDidFinish(_ navigation: Navigation) {
        if navigation.url.isDuckAIURL {
            featureDiscovery.setWasUsedBefore(.aiChat)
            injectLocalServerScriptsIfNeeded()
        }
    }

    private func registerFetchBridgeIfNeeded(on webView: WKWebView) {
        guard fetchBridgeRetainer == nil else { return }
        let (retainer, js) = DuckAILocalServerScriptInstaller.installFetchBridge(on: webView)
        fetchBridgeRetainer = retainer
        fetchBridgeJavaScript = js
        print("[HTTPSVR] TabExtension.registerFetchBridge: registered=\(retainer != nil)")
    }

    private func injectLocalServerScriptsIfNeeded() {
        guard let webView,
              let server = localServerProvider(),
              server.port > 0 else {
            print("[HTTPSVR] TabExtension.inject: skipped (webView=\(webView != nil), server=\(localServerProvider() != nil), port=\(localServerProvider()?.port ?? 0))")
            return
        }

        let port = server.port
        print("[HTTPSVR] TabExtension.inject: injecting port=\(port) into \(webView.url?.absoluteString ?? "nil")")

        // Inject the fetch bridge override (must run before port injection so fetch works)
        if let fetchJS = fetchBridgeJavaScript {
            webView.evaluateJavaScript(fetchJS)
        }

        let portJS = DuckAILocalServerScriptInstaller.portInjectionJavaScript(port: port)
        webView.evaluateJavaScript(portJS) { result, error in
            if let error {
                print("[HTTPSVR] TabExtension.inject: portJS FAILED: \(error)")
            } else {
                print("[HTTPSVR] TabExtension.inject: portJS succeeded")
            }
        }

        if !migrationDone {
            migrationDone = true
            let migrationJS = DuckAILocalServerScriptInstaller.migrationJavaScript(port: port)
            webView.evaluateJavaScript(migrationJS)
        }
    }
}

protocol AIChatProtocol: AnyObject, NavigationResponder {
    var aiChatUserScript: AIChatUserScript? { get }
    func setAIChatNativeHandoffData(payload: AIChatPayload)
    func setAIChatRestorationData(_ data: AIChatRestorationData?)
    func submitAIChatNativePrompt(_ prompt: AIChatNativePrompt)
    func submitAIChatPageContext(_ pageContext: AIChatPageContextData?)

    var pageContextRequestedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextConsumedPublisher: AnyPublisher<Void, Never> { get }
    var pageContextRemovedPublisher: AnyPublisher<Void, Never> { get }
    var chatRestorationDataPublisher: AnyPublisher<AIChatRestorationData?, Never> { get }
}

extension AIChatTabExtension: AIChatProtocol, TabExtension {
    func getPublicProtocol() -> AIChatProtocol { self }
}

extension TabExtensions {
    var aiChat: AIChatProtocol? { resolve(AIChatTabExtension.self) }
}
