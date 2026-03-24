//
//  MainViewController+AIChatLauncher.swift
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

import AIChat
import AppKit
import Combine
import Foundation

extension MainViewController {

    /// Creates the Duck.ai launcher and standalone floating window and wires them up.
    /// Call once from viewDidLoad, after setupAIChatHistorySidebar().
    func setupAIChatLauncher() {
        let privacyConfig = NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager
        let suggestionsReader = AIChatSuggestionsReader(
            suggestionsReader: SuggestionsReader(featureFlagger: featureFlagger, privacyConfig: privacyConfig),
            historySettings: AIChatHistorySettings(privacyConfig: privacyConfig)
        )

        let floatingCoordinator = AIChatStandaloneFloatingWindowCoordinator()
        standaloneFloatingWindowCoordinator = floatingCoordinator

        aiChatLauncherCoordinator = AIChatLauncherCoordinator(
            floatingWindowCoordinator: floatingCoordinator,
            suggestionsReader: suggestionsReader,
            onSettingsRequested: {
                Application.appDelegate.windowControllersManager.showPreferencesTab(withSelectedPane: .aiChat)
            },
            onNewChatWithQueryRequested: { [weak self] query in
                guard let self else { return }
                let settings = AIChatRemoteSettings()
                guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else { return }
                var items = components.queryItems ?? []
                items.removeAll { $0.name == AIChatURLParameters.promptQueryName || $0.name == AIChatURLParameters.autoSubmitPromptQueryName }
                items.append(URLQueryItem(name: AIChatURLParameters.promptQueryName, value: query))
                items.append(URLQueryItem(name: AIChatURLParameters.autoSubmitPromptQueryName, value: AIChatURLParameters.autoSubmitPromptQueryValue))
                components.queryItems = items
                guard let url = components.url else { return }
                tabCollectionViewModel.appendNewTab(with: .url(url, source: .ui), selected: true)
            },
            onVoiceChatRequested: { [weak self] in
                guard let self else { return }
                let settings = AIChatRemoteSettings()
                guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else { return }
                var items = components.queryItems ?? []
                items.removeAll { $0.name == AIChatURLParameters.modeName || $0.name == "chatID" }
                items.append(URLQueryItem(name: AIChatURLParameters.modeName, value: AIChatURLParameters.voiceModeValue))
                components.queryItems = items
                guard let url = components.url else { return }
                tabCollectionViewModel.appendNewTab(with: .url(url, source: .ui), selected: true)
            },
            onChatSelectedRequested: { [weak self] chatId in
                guard let self else { return }
                let settings = AIChatRemoteSettings()
                guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else { return }
                var items = components.queryItems ?? []
                items.removeAll { $0.name == AIChatURLParameters.modeName || $0.name == "chatID" }
                items.append(URLQueryItem(name: "chatID", value: chatId))
                components.queryItems = items
                guard let url = components.url else { return }
                tabCollectionViewModel.appendNewTab(with: .url(url, source: .ui), selected: true)
            }
        )

        // Bind toolbar button active state
        aiChatLauncherCoordinator?.$isLauncherOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen in
                self?.navigationBarViewController.updateAIChatLauncherButtonState(isActive: isOpen)
            }
            .store(in: &launcherCancellables)

        // Wire toolbar button closure
        navigationBarViewController.onAIChatLauncherButtonClicked = { [weak self] in
            guard let self, let window = view.window else { return }
            aiChatLauncherCoordinator?.toggleLauncher(from: window)
        }

        // Register ⌘K local event monitor. Stored in launcherKeyMonitor so it can be
        // explicitly removed when the window closes (NSEvent monitors must be removed manually).
        launcherKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.charactersIgnoringModifiers == "k",
                  event.modifierFlags.contains(.command) else { return event }
            // Only open if launcher is closed and this browser window is key
            guard view.window?.isKeyWindow == true,
                  aiChatLauncherCoordinator?.isLauncherOpen == false else { return event }
            guard let window = view.window else { return event }
            aiChatLauncherCoordinator?.toggleLauncher(from: window)
            return nil
        }

        // Tear down when the browser window closes to avoid a dangling event monitor
        // and to release the suggestions reader. The observer token is stored so it
        // can be removed to avoid leaking the block after the window closes.
        launcherWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let closingWindow = notification.object as? NSWindow,
                  closingWindow === view.window else { return }
            aiChatLauncherCoordinator?.tearDown()
            if let monitor = launcherKeyMonitor {
                NSEvent.removeMonitor(monitor)
                launcherKeyMonitor = nil
            }
            if let observer = launcherWindowCloseObserver {
                NotificationCenter.default.removeObserver(observer)
                launcherWindowCloseObserver = nil
            }
        }
    }
}
