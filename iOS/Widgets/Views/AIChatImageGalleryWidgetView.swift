//
//  AIChatImageGalleryWidgetView.swift
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

import SwiftUI
import WidgetKit
import Core
import DesignResourcesKit

struct AIChatImageGalleryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AIChatImageGalleryEntry

    private let cornerRadius: CGFloat = 8
    private let gap: CGFloat = 3

    private var columnsPerRow: Int { family == .systemLarge ? 3 : 4 }
    /// Fixed row height keeps cells from collapsing to zero in the widget's non-scrolling layout.
    private var rowHeight: CGFloat { family == .systemLarge ? 104 : 70 }
    private var maxImages: Int {
        switch family {
        case .systemLarge: return 9
        case .systemMedium: return 8
        default: return 1
        }
    }

    var body: some View {
        content
            .widgetContainerBackground()
    }

    @ViewBuilder
    private var content: some View {
        if entry.images.isEmpty {
            AIChatImageGalleryEmptyView()
        } else if family == .systemSmall {
            hero
        } else {
            grid
        }
    }

    // Small: the single most-recent image, full-bleed.
    @ViewBuilder
    private var hero: some View {
        if let image = entry.images.first, let thumbnail = entry.thumbnails[image.imageId] {
            Link(destination: AIChatImageGalleryEntry.deepLink(forChatId: image.chatId)) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .useFullColorRendering()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) { brandChip.padding(10) }
            }
        }
    }

    // Medium / Large: a photo grid built from fixed-height rows (no GeometryReader / flexible
    // aspect-ratio cells, both of which can collapse to zero height inside a widget).
    private var grid: some View {
        let images = Array(entry.images.prefix(maxImages))
        let rows = stride(from: 0, to: images.count, by: columnsPerRow).map { start in
            Array(images[start..<min(start + columnsPerRow, images.count)])
        }
        return VStack(spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowImages in
                HStack(spacing: gap) {
                    ForEach(rowImages, id: \.imageId) { image in
                        Link(destination: AIChatImageGalleryEntry.deepLink(forChatId: image.chatId)) {
                            cell(for: image)
                        }
                    }
                    // Keep cell widths consistent when the last row is partial.
                    if rowImages.count < columnsPerRow {
                        ForEach(0..<(columnsPerRow - rowImages.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) { brandChip.padding(10) }
    }

    private func cell(for image: WidgetImageEntry) -> some View {
        Group {
            if let thumbnail = entry.thumbnails[image.imageId] {
                Image(uiImage: thumbnail)
                    .resizable()
                    .useFullColorRendering()
                    .scaledToFill()
            } else {
                Color(designSystemColor: .surface)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var brandChip: some View {
        HStack(spacing: 4) {
            DuckAiLogo(size: 16)
            Text(UserText.recentChatsWidgetBrandTitle)
                .daxCaptionMedium()
                .foregroundStyle(Color(designSystemColor: .textPrimary))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Empty state

private struct AIChatImageGalleryEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            DuckAiLogo(size: 52)
            Text(UserText.imageGalleryWidgetEmptyMessage)
                .daxFootnoteRegular()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(designSystemColor: .textSecondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(16)
    }
}
