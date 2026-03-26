//
//  AIChatRecentChatsMenuCoordinator.swift
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
import DesignResourcesKitIcons

/// Shared coordinator for the Duck.ai recent chats NSMenu.
/// Used by the More Options menu, the main menu bar, and the toolbar button.
/// Conforms to NSMenuDelegate to lazily fetch suggestions each time a menu opens.
@MainActor
final class AIChatRecentChatsMenuCoordinator: NSObject, NSMenuDelegate {

    private let suggestionsReader: AIChatSuggestionsReader
    private var fetchTask: Task<Void, Never>?

    /// Tag applied to dynamically-inserted chat row items so they can be identified and replaced.
    private static let chatItemTag = 0xDCA1

    init(suggestionsReader: AIChatSuggestionsReader) {
        self.suggestionsReader = suggestionsReader
    }

    // MARK: - Public API

    /// Returns a new NSMenu configured with the Duck.ai history structure.
    /// The coordinator acts as delegate and handles async population of the chat list.
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.delegate = self
        menu.autoenablesItems = false

        // Top static actions
        menu.addItem(makeStaticItem(
            title: UserText.aiChatRecentChatsOpenDuckAI,
            action: #selector(openDuckAI(_:)),
            image: DesignSystemImages.Glyphs.Size16.aiChat
        ))
        menu.addItem(makeStaticItem(
            title: UserText.aiChatHistoryNewVoiceChat,
            action: #selector(openVoiceChat(_:)),
            image: DesignSystemImages.Glyphs.Size16.permissionMicrophone
        ))
        menu.addItem(makeStaticItem(
            title: UserText.aiChatRecentChatsCreateImage,
            action: #selector(openImageChat(_:)),
            image: DesignSystemImages.Glyphs.Size16.image
        ))

        menu.addItem(.separator())

        // "Recent Chats" section header
        let headerItem = NSMenuItem(title: UserText.aiChatHistoryRecentChats)
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Loading placeholder (replaced when the menu opens via menuWillOpen)
        menu.addItem(makeLoadingItem())

        menu.addItem(.separator())

        // Delete all chats
        menu.addItem(makeStaticItem(
            title: UserText.aiChatRecentChatsDeleteAll,
            action: #selector(deleteAllChats(_:)),
            image: nil
        ))

        return menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        fetchTask?.cancel()
        replaceDynamicItems(in: menu, with: [makeLoadingItem()])

        fetchTask = Task { [weak self, weak menu] in
            guard let self, let menu else { return }
            let result = await self.suggestionsReader.fetchSuggestions(query: nil)
            guard !Task.isCancelled else { return }
            let sorted = (result.pinned + result.recent).sorted {
                ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
            }
            if sorted.isEmpty {
                self.replaceDynamicItems(in: menu, with: [self.makeNoChatsItem()])
            } else {
                self.replaceDynamicItems(in: menu, with: sorted.map { self.makeChatItem(for: $0) })
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        fetchTask?.cancel()
        fetchTask = nil
    }

    // MARK: - Actions

    @objc private func openDuckAI(_ sender: NSMenuItem) {
        NSApp.delegateTyped.aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
    }

    @objc private func openVoiceChat(_ sender: NSMenuItem) {
        let url = buildModeURL(mode: AIChatURLParameters.voiceModeValue)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
    }

    @objc private func openImageChat(_ sender: NSMenuItem) {
        let url = buildModeURL(mode: AIChatURLParameters.imageModeValue)
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(with: .url(url), behavior: .newTab(selected: true))
    }

    @objc private func chatSelected(_ sender: NSMenuItem) {
        guard let chatId = sender.representedObject as? String else { return }
        NSApp.delegateTyped.aiChatTabOpener.openAIChatTab(
            with: .existingChat(chatId: chatId),
            behavior: .newTab(selected: true)
        )
    }

    @objc private func deleteAllChats(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = UserText.aiChatRecentChatsDeleteAllConfirmTitle
        alert.informativeText = UserText.aiChatRecentChatsDeleteAllConfirmMessage
        alert.addButton(withTitle: UserText.aiChatRecentChatsDeleteAllConfirmButton)
        alert.addButton(withTitle: UserText.cancel)
        alert.alertStyle = .warning
        // PoC: deletion is not yet implemented at the API level.
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // No-op for PoC — a future implementation would clear chat history via the SuggestionsReader.
    }

    // MARK: - Private Helpers

    private func replaceDynamicItems(in menu: NSMenu, with newItems: [NSMenuItem]) {
        // Remove all existing dynamic chat items
        for item in menu.items.filter({ $0.tag == Self.chatItemTag }) {
            menu.removeItem(item)
        }

        // Find the "Recent Chats" header and insert new items immediately after it
        guard let headerIndex = menu.items.firstIndex(where: {
            $0.title == UserText.aiChatHistoryRecentChats && !$0.isSeparatorItem
        }) else { return }

        for (offset, item) in newItems.enumerated() {
            item.tag = Self.chatItemTag
            menu.insertItem(item, at: headerIndex + 1 + offset)
        }
    }

    private func makeStaticItem(title: String, action: Selector, image: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image
        return item
    }

    private func makeLoadingItem() -> NSMenuItem {
        let item = NSMenuItem(title: UserText.aiChatRecentChatsLoading)
        item.isEnabled = false
        item.tag = Self.chatItemTag
        return item
    }

    private func makeNoChatsItem() -> NSMenuItem {
        let item = NSMenuItem(title: UserText.aiChatHistoryNoRecentChats)
        item.isEnabled = false
        item.tag = Self.chatItemTag
        return item
    }

    private func makeChatItem(for suggestion: AIChatSuggestion) -> NSMenuItem {
        let item = NSMenuItem(title: suggestion.title, action: #selector(chatSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = suggestion.chatId
        item.tag = Self.chatItemTag
        item.image = suggestion.isPinned
            ? DesignSystemImages.Glyphs.Size16.pin
            : DesignSystemImages.Glyphs.Size16.chat
        return item
    }

    private func buildModeURL(mode: String) -> URL {
        let settings = AIChatRemoteSettings()
        guard var components = URLComponents(url: settings.aiChatURL, resolvingAgainstBaseURL: false) else {
            return settings.aiChatURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == AIChatURLParameters.modeName }
        items.append(URLQueryItem(name: AIChatURLParameters.modeName, value: mode))
        components.queryItems = items
        return components.url ?? settings.aiChatURL
    }
}
