//
//  AIChatRecentChatsWidget.swift
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

import WidgetKit
import SwiftUI
import UIKit
import Core

struct AIChatRecentChatsEntry: TimelineEntry {
    let date: Date
    let chats: [WidgetChatEntry]
    let totalChatCount: Int
    let thumbnails: [String: UIImage]
    let isPreview: Bool

    /// Deep link that opens a specific chat from a widget row.
    static func deepLink(forChatId chatId: String) -> URL {
        AIChatWidgetDeepLink.url(forChatId: chatId, source: WidgetSourceType.recentChatsWidget.rawValue)
    }

    /// Sample content shown in the widget gallery / previews.
    static var sample: AIChatRecentChatsEntry {
        let chats = [
            WidgetChatEntry(chatId: "1", title: "Trip ideas for Lisbon", lastEdit: "", hasImageThumbnail: false),
            WidgetChatEntry(chatId: "2", title: "Explain quantum computing", lastEdit: "", hasImageThumbnail: false),
            WidgetChatEntry(chatId: "3", title: "Dinner recipe with salmon", lastEdit: "", hasImageThumbnail: false),
            WidgetChatEntry(chatId: "4", title: "Summarize this article", lastEdit: "", hasImageThumbnail: false)
        ]
        return AIChatRecentChatsEntry(date: Date(), chats: chats, totalChatCount: chats.count, thumbnails: [:], isPreview: true)
    }
}

struct AIChatRecentChatsProvider: TimelineProvider {

    func placeholder(in context: Context) -> AIChatRecentChatsEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (AIChatRecentChatsEntry) -> Void) {
        completion(makeEntry(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIChatRecentChatsEntry>) -> Void) {
        // `.never`: the main app drives reloads via WidgetCenter when the mirror changes.
        completion(Timeline(entries: [makeEntry(isPreview: context.isPreview)], policy: .never))
    }

    private func makeEntry(isPreview: Bool) -> AIChatRecentChatsEntry {
        // In the gallery, show curated sample content rather than an empty box.
        if isPreview {
            return .sample
        }

        // No flag gate: the sync engine wipes the mirror when the setting is off, so "no data on
        // disk" is the safety guarantee. The widget just renders whatever exists.
        guard let location = AIChatWidgetDataLocation.appGroup() else {
            return AIChatRecentChatsEntry(date: Date(), chats: [], totalChatCount: 0, thumbnails: [:], isPreview: false)
        }

        let snapshot = (try? JSONDecoder().decode(WidgetChatSnapshot.self, from: Data(contentsOf: location.chatsFileURL)))
            ?? WidgetChatSnapshot(totalChatCount: 0, chats: [])

        var thumbnails: [String: UIImage] = [:]
        for chat in snapshot.chats where chat.hasImageThumbnail {
            if let data = try? Data(contentsOf: location.thumbnailURL(forChatId: chat.chatId)),
               let image = UIImage(data: data) {
                thumbnails[chat.chatId] = image.toSRGB()
            }
        }

        return AIChatRecentChatsEntry(date: Date(),
                                      chats: snapshot.chats,
                                      totalChatCount: snapshot.totalChatCount,
                                      thumbnails: thumbnails,
                                      isPreview: false)
    }
}

struct AIChatRecentChatsWidget: Widget {
    let kind: String = "AIChatRecentChatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIChatRecentChatsProvider()) { entry in
            AIChatRecentChatsWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.recentChatsWidgetGalleryDisplayName)
        .description(UserText.recentChatsWidgetGalleryDescription)
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
