//
//  AIChatImageGalleryWidget.swift
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

struct AIChatImageGalleryEntry: TimelineEntry {
    let date: Date
    let images: [WidgetImageEntry]
    let thumbnails: [String: UIImage]
    let isPreview: Bool

    /// Deep link that opens the chat that produced a given image.
    static func deepLink(forChatId chatId: String) -> URL {
        AIChatWidgetDeepLink.url(forChatId: chatId, source: WidgetSourceType.imageGalleryWidget.rawValue)
    }
}

struct AIChatImageGalleryProvider: TimelineProvider {

    func placeholder(in context: Context) -> AIChatImageGalleryEntry {
        makeEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (AIChatImageGalleryEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AIChatImageGalleryEntry>) -> Void) {
        // `.never`: the main app drives reloads via WidgetCenter when the mirror changes.
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> AIChatImageGalleryEntry {
        // No flag gate here: the sync engine wipes the mirror when the setting is off, so
        // "no data on disk" is the safety guarantee. The widget just renders whatever exists.
        guard let location = AIChatWidgetDataLocation.appGroup() else {
            return AIChatImageGalleryEntry(date: Date(), images: [], thumbnails: [:], isPreview: false)
        }

        let images = (try? JSONDecoder().decode([WidgetImageEntry].self, from: Data(contentsOf: location.imagesFileURL))) ?? []

        var thumbnails: [String: UIImage] = [:]
        for image in images {
            if let data = try? Data(contentsOf: location.galleryImageURL(forImageId: image.imageId)),
               let uiImage = UIImage(data: data) {
                thumbnails[image.imageId] = uiImage.toSRGB()
            }
        }

        #if DEBUG
        print("DUCKAI-WIDGET-EXT [gallery] container=\(location.rootURL.path)")
        print("DUCKAI-WIDGET-EXT [gallery] images.json exists=\(FileManager.default.fileExists(atPath: location.imagesFileURL.path)) decoded=\(images.count) thumbnails=\(thumbnails.count)")
        #endif

        return AIChatImageGalleryEntry(date: Date(), images: images, thumbnails: thumbnails, isPreview: false)
    }
}

struct AIChatImageGalleryWidget: Widget {
    let kind: String = "AIChatImageGalleryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIChatImageGalleryProvider()) { entry in
            AIChatImageGalleryWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.imageGalleryWidgetGalleryDisplayName)
        .description(UserText.imageGalleryWidgetGalleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
