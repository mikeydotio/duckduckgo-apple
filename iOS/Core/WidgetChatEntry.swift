//
//  WidgetChatEntry.swift
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

import Foundation

/// Minimal mirror of a Duck.ai chat, written to the shared app group so the recent-chats
/// widget can render it.
///
/// Native chat storage (GRDB + filesystem) is intentionally not in an app group and is never
/// moved; this struct carries only what the widget displays — no messages, model, file refs,
/// or pinned state.
public struct WidgetChatEntry: Codable, Equatable {

    public let chatId: String
    public let title: String

    /// ISO-8601 string as supplied by native storage, used for ordering.
    public let lastEdit: String

    /// Whether this chat produced generated images (shown with a photo icon in the widget).
    public let isImageGeneration: Bool

    /// Whether the user pinned this chat. Pinned chats sort to the top and show a pin icon.
    public let pinned: Bool

    public init(chatId: String, title: String, lastEdit: String, isImageGeneration: Bool, pinned: Bool = false) {
        self.chatId = chatId
        self.title = title
        self.lastEdit = lastEdit
        self.isImageGeneration = isImageGeneration
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case chatId, title, lastEdit, isImageGeneration, pinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chatId = try container.decode(String.self, forKey: .chatId)
        title = try container.decode(String.self, forKey: .title)
        lastEdit = try container.decode(String.self, forKey: .lastEdit)
        // Tolerate older mirrors written before these fields existed / were renamed.
        isImageGeneration = try container.decodeIfPresent(Bool.self, forKey: .isImageGeneration) ?? false
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

/// Envelope written to the app group: the most-recent chats the widget renders, plus the total
/// number of chats the user has (so the widget can show an accurate count even though only the
/// top few are mirrored).
public struct WidgetChatSnapshot: Codable, Equatable {
    public let totalChatCount: Int
    public let chats: [WidgetChatEntry]

    public init(totalChatCount: Int, chats: [WidgetChatEntry]) {
        self.totalChatCount = totalChatCount
        self.chats = chats
    }
}

/// A single Duck.ai generated image surfaced by the image gallery widget. `imageId` is the native
/// file UUID (also the gallery thumbnail filename); `chatId` is the chat that produced it, used to
/// deep link back into the conversation.
public struct WidgetImageEntry: Codable, Equatable {
    public let imageId: String
    public let chatId: String

    public init(imageId: String, chatId: String) {
        self.imageId = imageId
        self.chatId = chatId
    }
}
