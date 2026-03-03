//
//  PromoDebugMenu.swift
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
import BrowserServicesKit
import Combine
import Foundation
import Utilities

/// **DEBUG MENU for Promo Queue**
///
/// This menu provides tools to force-show promos for testing, bypassing all evaluation rules.
/// Located in: Debug menu → "Promo Queue"
///
/// **Menu Items:**
/// - "Fire Test Trigger" (debug/review builds only) – sends a test notification to trigger promos that listen for it
/// - For each promo: parent item with status, submenu with Force Show, Undismiss, Undismiss + Clear History
/// - "Advance Simulated Date by 1 Day" – advances the simulated "now" for cooldown checks
/// - "Reset Simulated Date" – clears the simulated date (disabled when none set)
/// - "Reset All Promo State" – clears debug date override and all promo history
/// - When no promos: disabled "No promos registered"
///
/// **Force-show behavior:**
/// - Does not affect history, cooldowns, or other promos
/// - Does not add to activeSessions
final class PromoDebugMenu: NSMenu {

    private var cancellables = Set<AnyCancellable>()
    private var cachedHistory: [String: PromoHistoryRecord] = [:]
    private var simulatedDate: Date?

    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter
    }()

    init() {
        super.init(title: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        removeAllItems()
        buildMenuItems()
    }

    private func buildMenuItems() {
        guard let promoService = NSApp.delegateTyped.promoService else {
            let item = NSMenuItem(title: "Promo Queue unavailable (feature flag off)", action: nil)
            item.isEnabled = false
            addItem(item)
            return
        }

        let promos = PromoServiceFactory.promos

        if promos.isEmpty {
            let item = NSMenuItem(title: "No promos registered", action: nil)
            item.isEnabled = false
            addItem(item)
            return
        }

        promoService.allHistoryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.cachedHistory = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            }
            .store(in: &cancellables)

#if DEBUG || REVIEW
        let fireItem = NSMenuItem(title: "Fire Test Trigger", action: #selector(fireTestTrigger), keyEquivalent: "t")
        fireItem.keyEquivalentModifierMask = [.command, .shift, .option, .control]
        fireItem.target = self
        fireItem.setAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.fireTestTriggerMenuItem)
        addItem(fireItem)
        addItem(.separator())
#endif

        for promo in promos {
            let status = statusString(for: promo.id)
            let parentItem = NSMenuItem(title: "\(promo.id)  \(status)", action: nil)

            let submenu = NSMenu()
            let forceShowItem = NSMenuItem(title: "Force Show", action: #selector(forceShowPromo(_:)), keyEquivalent: "")
            forceShowItem.representedObject = promo.id
            forceShowItem.target = self
            submenu.addItem(forceShowItem)

            let undismissItem = NSMenuItem(title: "Undismiss", action: #selector(undismissPromo(_:)), keyEquivalent: "")
            undismissItem.representedObject = promo.id
            undismissItem.target = self
            submenu.addItem(undismissItem)

            let undismissClearItem = NSMenuItem(title: "Undismiss + Clear History", action: #selector(undismissPromoAndClearHistory(_:)), keyEquivalent: "")
            undismissClearItem.representedObject = promo.id
            undismissClearItem.target = self
            submenu.addItem(undismissClearItem)

            parentItem.submenu = submenu
            addItem(parentItem)
        }

        addItem(.separator())

        let advanceHourItem = NSMenuItem(title: "Advance Simulated Date by 1 Hour", action: #selector(advanceSimulatedDateByHour), keyEquivalent: "")
        advanceHourItem.target = self
        advanceHourItem.setAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.advanceSimulatedDate1Hour)
        addItem(advanceHourItem)

        let advanceDayItem = NSMenuItem(title: "Advance Simulated Date by 1 Day", action: #selector(advanceSimulatedDateByDay), keyEquivalent: "")
        advanceDayItem.target = self
        advanceDayItem.setAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.advanceSimulatedDate1Day)
        addItem(advanceDayItem)

        let resetDateItem = NSMenuItem(title: "Reset Simulated Date", action: #selector(resetSimulatedDate), keyEquivalent: "")
        resetDateItem.target = self
        resetDateItem.isEnabled = simulatedDate != nil
        resetDateItem.setAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.resetSimulatedDate)
        addItem(resetDateItem)

        addItem(.separator())

        let resetItem = NSMenuItem(title: "Reset All Promo State", action: #selector(resetAllPromoState), keyEquivalent: "")
        resetItem.target = self
        resetItem.setAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.resetAllPromoState)
        addItem(resetItem)
    }

    private func statusString(for promoId: String) -> String {
        guard let record = cachedHistory[promoId], record.lastDismissed != nil else { return "eligible" }
        if record.isPermanentlyDismissed { return "dismissed" }
        guard let next = record.nextEligibleDate else { return "eligible" }
        if next > Date() {
            return "on cooldown until \(Self.dateFormatter.string(from: next))"
        }
        return "eligible (cooldown expired)"
    }

    @objc private func fireTestTrigger() {
#if DEBUG || REVIEW
        NotificationCenter.default.post(name: .promoDebugTestTrigger, object: nil)
#endif
    }

    @objc private func forceShowPromo(_ sender: NSMenuItem) {
        guard let promoId = sender.representedObject as? String else { return }
        NSApp.delegateTyped.promoService?.forceShow(promoId: promoId)
    }

    @objc private func undismissPromo(_ sender: NSMenuItem) {
        guard let promoId = sender.representedObject as? String else { return }
        NSApp.delegateTyped.promoService?.undismiss(promoId: promoId, clearHistory: false)
    }

    @objc private func undismissPromoAndClearHistory(_ sender: NSMenuItem) {
        guard let promoId = sender.representedObject as? String else { return }
        NSApp.delegateTyped.promoService?.undismiss(promoId: promoId, clearHistory: true)
    }

    @objc private func advanceSimulatedDateByDay() {
        advanceSimulatedDate(by: .day)
    }

    @objc private func advanceSimulatedDateByHour() {
        advanceSimulatedDate(by: .hours(1))
    }

    private func advanceSimulatedDate(by interval: TimeInterval) {
        simulatedDate = (simulatedDate ?? Date()).addingTimeInterval(interval)
        NSApp.delegateTyped.promoService?.setDebugSimulatedDate(simulatedDate)
    }

    @objc private func resetSimulatedDate() {
        simulatedDate = nil
        NSApp.delegateTyped.promoService?.setDebugSimulatedDate(nil)
    }

    @objc private func resetAllPromoState() {
        simulatedDate = nil
        NSApp.delegateTyped.promoService?.resetDebugState()
    }
}
