//
//  AIChatDebugMenu.swift
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

import AIChat
import AIChatDebugServer
import DebugServer
import AppKit
import Persistence

final class AIChatDebugMenu: NSMenu {
    private var storage = DefaultAIChatPreferencesStorage()
    private let customURLLabelMenuItem = NSMenuItem(title: "")
    private let debugStorage: any KeyedStoring<AIChatDebugURLSettings>

    private var storageDebugServer: DuckAiStorageDebugServer?
    private lazy var storageServerMenuItem = NSMenuItem(
        title: "Start Storage Server",
        action: #selector(toggleStorageServer),
        target: self
    )

    /// Lets a presenter simulate a subscription tier (and, for the free tier, StoreKit free-trial
    /// eligibility) so the gated model / reasoning-effort / upsell-copy flows can be demoed on a
    /// single build without a real subscription.
    private lazy var simulatedTierMenuItem: NSMenuItem = makeSimulatedTierMenuItem()

    init(debugStorage: (any KeyedStoring<AIChatDebugURLSettings>)? = nil) {
        self.debugStorage = if let debugStorage { debugStorage } else { UserDefaults.standard.keyedStoring() }
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Web Communication") {
                NSMenuItem(title: "Set Custom URL", action: #selector(setCustomURL))
                    .targetting(self)
                NSMenuItem(title: "Reset Custom URL", action: #selector(resetCustomURL))
                    .targetting(self)
                customURLLabelMenuItem
            }

            NSMenuItem.separator()

            NSMenuItem(title: "Reset Toggle Animation", action: #selector(resetToggleAnimation))
                .targetting(self)

            NSMenuItem.separator()

            simulatedTierMenuItem

            NSMenuItem.separator()

            storageServerMenuItem
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu State Update

    override func update() {
        updateWebUIMenuItemsState()
        updateSimulatedTierState()
    }

    // MARK: - Simulated Subscription Tier

    private func makeSimulatedTierMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Simulate Subscription Tier", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let options: [(title: String, raw: String?)] = [
            ("Off (Use real subscription)", nil),
            ("Free (Trial Eligible)", AIChatDebugSimulatedTier.freeTrialEligible.rawValue),
            ("Free (Trial Ineligible)", AIChatDebugSimulatedTier.freeTrialIneligible.rawValue),
            ("Plus", AIChatDebugSimulatedTier.plus.rawValue),
            ("Pro", AIChatDebugSimulatedTier.pro.rawValue)
        ]
        for option in options {
            let item = NSMenuItem(title: option.title, action: #selector(setSimulatedTier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.raw
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func setSimulatedTier(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String
        UserDefaults.standard.duckAISimulatedTier = raw.flatMap(AIChatDebugSimulatedTier.init(rawValue:))
        updateSimulatedTierState()
    }

    private func updateSimulatedTierState() {
        let current = UserDefaults.standard.duckAISimulatedTier?.rawValue
        for item in simulatedTierMenuItem.submenu?.items ?? [] {
            item.state = (item.representedObject as? String) == current ? .on : .off
        }
    }

    @objc func setCustomURL() {
        showCustomURLAlert { [weak self] value in

            guard let value = value, let url = URL(string: value), url.isValid else { return false }

            self?.debugStorage.customURL = value
            return true
        }
    }

    @objc func resetCustomURL() {
        debugStorage.resetCustomURL()
        updateWebUIMenuItemsState()
    }

    @objc func resetToggleAnimation() {
        UserDefaults.standard.hasInteractedWithSearchDuckAIToggle = false
    }

    @objc func toggleStorageServer() {
        if let server = storageDebugServer {
            server.stop()
            storageDebugServer = nil
            storageServerMenuItem.title = "Start Storage Server"
        } else {
            guard let handler = NSApp.delegateTyped.duckAiNativeStorageHandler else {
                let alert = NSAlert()
                alert.messageText = "Native storage is not available"
                alert.informativeText = "The duckAiNativeStorage feature flag may be disabled."
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }

            do {
                let server = DuckAiStorageDebugServer(storageHandler: handler)
                server.stateDidChange = { [weak self] state in
                    Task { @MainActor in
                        self?.handleStorageServerStateChange(state)
                    }
                }
                try server.start()
                storageDebugServer = server
                storageServerMenuItem.title = "Starting Storage Server…"
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to start storage server"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @MainActor
    private func handleStorageServerStateChange(_ state: ServerState) {
        switch state {
        case .running(let port):
            storageServerMenuItem.title = "Stop Storage Server (localhost:\(port))"
            if let url = URL(string: "http://localhost:\(port)") {
                Application.appDelegate.windowControllersManager.showTab(with: .url(url, source: .ui))
            }
        case .failed(let message):
            storageDebugServer = nil
            storageServerMenuItem.title = "Start Storage Server"
            let alert = NSAlert()
            alert.messageText = "Storage server failed"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        default:
            break
        }
    }

    private func updateWebUIMenuItemsState() {
        customURLLabelMenuItem.title = "Custom URL: [\(debugStorage.customURL ?? "")]"
    }

    private func showCustomURLAlert(callback: @escaping (String?) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Enter URL"
        alert.addButton(withTitle: "Accept")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = inputTextField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if !callback(inputTextField.stringValue) {
                let invalidAlert = NSAlert()
                invalidAlert.messageText = "Invalid URL"
                invalidAlert.informativeText = "Please enter a valid URL."
                invalidAlert.addButton(withTitle: "OK")
                invalidAlert.runModal()
            }
        } else {
            _ = callback(nil)
        }
    }
}

// MARK: - Simulated Subscription Tier storage

/// A debug-menu override of the resolved subscription tier and, for the free tier, StoreKit
/// free-trial eligibility — the two vary independently in production (a free user may or may not
/// still be eligible for an introductory trial), so simulating just a tier isn't enough to demo
/// the "Try for free" vs "Upgrade" copy split.
enum AIChatDebugSimulatedTier: String {
    case freeTrialEligible
    case freeTrialIneligible
    case plus
    case pro

    var userTier: AIChatUserTier {
        switch self {
        case .freeTrialEligible, .freeTrialIneligible: return .free
        case .plus: return .plus
        case .pro: return .pro
        }
    }

    /// `nil` for Plus/Pro: trial eligibility only bears on the free tier, so the real
    /// subscription/StoreKit-backed check applies there instead (moot in practice, since
    /// `userTier` alone already routes those cases away from the eligibility question).
    var isEligibleForFreeTrial: Bool? {
        switch self {
        case .freeTrialEligible: return true
        case .freeTrialIneligible: return false
        case .plus, .pro: return nil
        }
    }
}

extension UserDefaults {
    private static let duckAISimulatedTierKey = "aichat.debug.simulatedSubscriptionTier"

    /// Debug-only override of the resolved subscription tier (and free-trial eligibility), used to
    /// demo gated model / reasoning-effort / upsell-copy flows without a real subscription. `nil`
    /// means "use the real subscription".
    var duckAISimulatedTier: AIChatDebugSimulatedTier? {
        get { string(forKey: Self.duckAISimulatedTierKey).flatMap(AIChatDebugSimulatedTier.init(rawValue:)) }
        set { set(newValue?.rawValue, forKey: Self.duckAISimulatedTierKey) }
    }
}
