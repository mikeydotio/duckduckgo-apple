//
//  DuckAIStatusBarController.swift
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
import DesignResourcesKitIcons

@MainActor
final class DuckAIStatusBarController: NSObject {

    /// Called when the user left-clicks the status item or selects "Open Duck.ai".
    var onOpenRequested: (() -> Void)?

    private var statusItem: NSStatusItem?

    var isInstalled: Bool { statusItem != nil }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = DesignSystemImages.Glyphs.Size16.aiChat
        image.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = UserText.aiChatStatusBarTooltip
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item
    }

    func uninstall() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc
    private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showContextMenu()
        } else {
            onOpenRequested?()
        }
    }

    private func showContextMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: UserText.aiChatStatusBarOpenItem,
            action: #selector(menuOpenSelected),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: UserText.mainMenuAppQuitDuckDuckGo,
            action: #selector(menuQuitSelected),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // popUpMenu auto-dismisses; clearing the temporary `menu` afterwards lets a
        // subsequent left-click go through `statusItemClicked` again.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc
    private func menuOpenSelected() {
        onOpenRequested?()
    }

    @objc
    private func menuQuitSelected() {
        NSApp.terminate(nil)
    }
}
