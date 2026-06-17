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
import os.log

struct AIChatImageGalleryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AIChatImageGalleryEntry

    private let gap: CGFloat = 3
    private let inset: CGFloat = 8

    /// iOS rounds the home-screen widget container at ~21.5pt. Insetting the grid by `inset` and
    /// rounding each cell to (container radius − inset) keeps the gap uniform around the corner, so
    /// the image cells read as concentric with the widget itself (Apple HIG).
    private let widgetCornerRadius: CGFloat = 21.5
    private var cornerRadius: CGFloat { max(widgetCornerRadius - inset, 8) }

    private var columnsPerRow: Int { family == .systemLarge ? 3 : 4 }
    /// Fixed row height keeps cells from collapsing to zero in the widget's non-scrolling layout.
    /// Sized so the rows fit the family's height (Large: 3 rows, Medium: 2 rows) without clipping.
    private var rowHeight: CGFloat { family == .systemLarge ? 104 : 66 }
    private var maxImages: Int {
        switch family {
        case .systemLarge: return 9
        case .systemMedium: return 8
        default: return 1
        }
    }

    var body: some View {
        let _ = Logger.duckAiWidget.notice("DUCKAI-WIDGET [ext/gallery VIEW] body: family=\(String(describing: family), privacy: .public) images=\(entry.images.count, privacy: .public) thumbnails=\(entry.thumbnails.count, privacy: .public)")
        return content
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

    // Small: the single most-recent image, full-bleed. A GeometryReader gives the image a concrete
    // frame (the proven recipe — see `cell(for:width:)`).
    @ViewBuilder
    private var hero: some View {
        if let image = entry.images.first, let thumbnail = entry.thumbnails[image.imageId] {
            Link(destination: AIChatImageGalleryEntry.deepLink(forChatId: image.chatId)) {
                GeometryReader { geo in
                    Image(uiImage: thumbnail)
                        .resizable()
                        .useFullColorRendering()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(alignment: .bottomLeading) { brandChip.padding(10) }
                }
            }
        }
    }

    // Medium / Large: a photo grid. A single GeometryReader resolves the concrete cell width so each
    // image gets a FIXED frame — the same recipe the chats-widget thumbnail uses. `aspectRatio(.fill)`
    // against a flexible (`maxWidth: .infinity`) width does not render inside a widget; a fixed frame does.
    private var grid: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - inset * 2
            let cellWidth = (availableWidth - gap * CGFloat(columnsPerRow - 1)) / CGFloat(columnsPerRow)
            let images = Array(entry.images.prefix(maxImages))
            let rows = stride(from: 0, to: images.count, by: columnsPerRow).map { start in
                Array(images[start..<min(start + columnsPerRow, images.count)])
            }
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, rowImages in
                    HStack(spacing: gap) {
                        ForEach(rowImages, id: \.imageId) { image in
                            Link(destination: AIChatImageGalleryEntry.deepLink(forChatId: image.chatId)) {
                                cell(for: image, width: cellWidth)
                            }
                        }
                        // Left-align a partial final row.
                        if rowImages.count < columnsPerRow {
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(inset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .overlay(alignment: .topTrailing) { brandChip.padding(10) }
        }
    }

    private func cell(for image: WidgetImageEntry, width: CGFloat) -> some View {
        // Proven recipe (matches the working chats thumbnail): the modifiers are applied directly to
        // the Image and end in a FIXED frame, then the result is clipped. The surface background shows
        // through only while a thumbnail is missing.
        ZStack {
            Color(designSystemColor: .surface)
            if let thumbnail = entry.thumbnails[image.imageId] {
                Image(uiImage: thumbnail)
                    .resizable()
                    .useFullColorRendering()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: rowHeight)
            }
        }
        .frame(width: width, height: rowHeight)
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
