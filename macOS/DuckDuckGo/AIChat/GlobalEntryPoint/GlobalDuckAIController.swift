//
//  GlobalDuckAIController.swift
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

import AppKit
import Combine
import LoginItems
import os.log

/// Coordinates the OS-level Duck.ai entry point: status bar item, global keyboard shortcut,
/// floating omnibar, and login-item registration. Reconciles its state from
/// `AIChatPreferences.isGlobalShortcutEnabled` — flipping the toggle installs/uninstalls
/// the menu-bar icon, registers/unregisters the system-wide hot key, and registers/
/// unregisters DDG as a login item.
@MainActor
final class GlobalDuckAIController {

    private static let logger = Logger(subsystem: "Duck.ai Global Entry Point", category: "")

    private let preferences: AIChatPreferences
    private let statusBar = DuckAIStatusBarController()
    private let floatingOmnibar = DuckAIFloatingOmnibarWindowController()
    private let shortcutMonitor = DuckAIGlobalShortcutMonitor()
    private let loginItem: LoginItem = .mainApp(defaults: .standard, logger: GlobalDuckAIController.logger)
    private var cancellables = Set<AnyCancellable>()

    init(preferences: AIChatPreferences) {
        self.preferences = preferences

        statusBar.onOpenRequested = { [weak self] in
            self?.handleOpenRequested()
        }

        shortcutMonitor.onTriggered = { [weak self] in
            self?.handleOpenRequested()
        }

        preferences.$isGlobalShortcutEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.apply(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func apply(enabled: Bool) {
        if enabled {
            statusBar.install()
            shortcutMonitor.start()
            do {
                try loginItem.enable()
            } catch {
                Self.logger.error("Failed to register Duck.ai login item: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            statusBar.uninstall()
            shortcutMonitor.stop()
            do {
                try loginItem.disable()
            } catch {
                Self.logger.error("Failed to unregister Duck.ai login item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleOpenRequested() {
        floatingOmnibar.toggle()
    }
}
