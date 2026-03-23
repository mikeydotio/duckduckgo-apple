//
//  AIChatHistoryMenuBuilder.swift
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
import AIChat
import DesignResourcesKitIcons

/// Builds an NSMenu populated with duck.ai chat history suggestions.
@MainActor
enum AIChatHistoryMenuBuilder {

    /// Builds a menu from pinned and recent suggestions.
    /// - Parameters:
    ///   - pinned: Pinned chat suggestions, shown first.
    ///   - recent: Recent chat suggestions, shown after pinned.
    ///   - target: The target for the selection actions.
    ///   - action: Selector called when a chat item is selected. The sender is the `NSMenuItem`
    ///             whose `representedObject` is the `chatId` string.
    ///   - showAllAction: Selector called when "Show all Duck.ai chats" is selected.
    /// - Returns: A populated `NSMenu`. If both arrays are empty, contains a single disabled "No recent chats" item,
    ///            followed by a separator and the "Show all" item.
    static func buildMenu(pinned: [AIChatSuggestion],
                          recent: [AIChatSuggestion],
                          target: AnyObject,
                          action: Selector,
                          showAllAction: Selector) -> NSMenu {
        let menu = NSMenu()
        let all = pinned + recent

        if all.isEmpty {
            let noChatsItem = NSMenuItem(title: UserText.aiChatHistoryNoRecentChats, action: nil, keyEquivalent: "")
            noChatsItem.isEnabled = false
            menu.addItem(noChatsItem)
        } else {
            for suggestion in all {
                let item = NSMenuItem(title: suggestion.title, action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = suggestion.chatId
                item.image = suggestion.isPinned
                    ? DesignSystemImages.Glyphs.Size16.pin
                    : DesignSystemImages.Glyphs.Size16.chat
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let showAllItem = NSMenuItem(title: UserText.aiChatHistoryShowAll, action: showAllAction, keyEquivalent: "")
        showAllItem.target = target
        menu.addItem(showAllItem)

        return menu
    }
}
