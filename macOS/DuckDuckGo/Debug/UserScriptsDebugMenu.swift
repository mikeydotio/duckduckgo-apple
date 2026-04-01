//
//  UserScriptsDebugMenu.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Debug submenu for disabling individual user scripts per-tab or globally.
/// Both per-tab and global changes are session-only and reset on app relaunch.
@MainActor
final class UserScriptsDebugMenu: NSMenu, NSMenuDelegate {

    override init(title: String) {
        super.init(title: title)
        self.delegate = self
        self.autoenablesItems = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(title: "Disable Individual Scripts")
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        removeAllItems()

        let scriptNames = currentTabScriptNames()

        addSectionHeader("[Current Tab]")
        if scriptNames.isEmpty {
            let item = NSMenuItem(title: "No scripts loaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            addItem(item)
        } else {
            for name in scriptNames {
                let isDisabled = currentTabUserScripts()?.perTabDisabled.contains(name) ?? false
                addItem(makeScriptItem(name: name, action: #selector(togglePerTab(_:)), isDisabled: isDisabled))
            }
        }

        addItem(.separator())

        addSectionHeader("[Global]")
        if scriptNames.isEmpty {
            let item = NSMenuItem(title: "No scripts loaded", action: nil, keyEquivalent: "")
            item.isEnabled = false
            addItem(item)
        } else {
            for name in scriptNames {
                let isDisabled = UserScriptDisabledStore.shared.globallyDisabled.contains(name)
                addItem(makeScriptItem(name: name, action: #selector(toggleGlobal(_:)), isDisabled: isDisabled))
            }
        }
    }

    private func addSectionHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    private func makeScriptItem(name: String, action: Selector, isDisabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
        item.representedObject = name
        item.target = self
        item.state = isDisabled ? .on : .off
        item.isEnabled = true
        return item
    }

    // MARK: - Helpers

    private func currentTabUserScripts() -> UserScripts? {
        let tab = Application.appDelegate.windowControllersManager.selectedTab
        return tab?.userContentController?.contentBlockingAssets?.userScripts as? UserScripts
    }

    private func currentTabScriptNames() -> [String] {
        guard let scripts = currentTabUserScripts() else { return [] }
        return scripts.userScripts
            .map { $0.debugName }
            .sorted()
    }

    // MARK: - Actions

    @objc private func togglePerTab(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let tab = Application.appDelegate.windowControllersManager.selectedTab,
              let userScripts = tab.userContentController?.contentBlockingAssets?.userScripts as? UserScripts
        else { return }

        if userScripts.perTabDisabled.contains(name) {
            userScripts.perTabDisabled.remove(name)
        } else {
            userScripts.perTabDisabled.insert(name)
        }

        Task { @MainActor in
            await tab.userContentController?.reinstallUserScripts()
            tab.reload()
        }
    }

    @objc private func toggleGlobal(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }

        let store = UserScriptDisabledStore.shared
        if store.globallyDisabled.contains(name) {
            store.globallyDisabled.remove(name)
        } else {
            store.globallyDisabled.insert(name)
        }

        let allTabs = Application.appDelegate.windowControllersManager.mainWindowControllers
            .flatMap { wc -> [Tab] in
                let vm = wc.mainViewController.tabCollectionViewModel
                let regular = vm.tabCollection.tabs
                let pinned = vm.pinnedTabsCollection?.tabs ?? []
                return regular + pinned
            }

        Task { @MainActor in
            for tab in allTabs {
                await tab.userContentController?.reinstallUserScripts()
                tab.reload()
            }
        }
    }
}
