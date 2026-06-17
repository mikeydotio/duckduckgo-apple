//
//  AIChatWidgetSyncEngine.swift
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
import Combine
import UIKit
import Core
import AIChat
import DuckAiDataStore
import WidgetKit
import os.log

/// Mirrors a minimal subset of Duck.ai native-storage chats into the shared app group so the
/// recent-chats widget can read them.
///
/// Native storage (GRDB + filesystem) is never moved; this is a one-way mirror. The mirror only
/// exists while the user keeps both the global AI Chat toggle and the widget toggle on — when
/// either is turned off the mirror is wiped. The whole engine is implicitly gated by the
/// `aiChatNativeStorage` feature flag: when that is off the storage handler is `nil` and the
/// engine does nothing.
final class AIChatWidgetSyncEngine {

    static let maxChats = 6
    static let maxGalleryImages = 12

    /// Longest edge of a gallery image, in points.
    private static let galleryMaxDimension: CGFloat = 320

    private let storage: DuckAiNativeObservableStorage?
    private let settings: AIChatSettingsProvider
    private let dataLocation: AIChatWidgetDataLocation?
    private let notificationCenter: NotificationCenter
    private let reloadWidgets: () -> Void
    private let liveUpdateDebounce: DispatchQueue.SchedulerTimeType.Stride
    private let queue = DispatchQueue(label: "com.duckduckgo.aichat.widget.sync")

    private var cancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?

    init(storage: DuckAiNativeObservableStorage?,
         settings: AIChatSettingsProvider,
         dataLocation: AIChatWidgetDataLocation?,
         notificationCenter: NotificationCenter = .default,
         liveUpdateDebounce: DispatchQueue.SchedulerTimeType.Stride = .seconds(2),
         reloadWidgets: @escaping () -> Void = { DispatchQueue.main.async { WidgetCenter.shared.reloadAllTimelines() } }) {
        self.storage = storage
        self.settings = settings
        self.dataLocation = dataLocation
        self.notificationCenter = notificationCenter
        self.liveUpdateDebounce = liveUpdateDebounce
        self.reloadWidgets = reloadWidgets
    }

    deinit {
        if let settingsObserver {
            notificationCenter.removeObserver(settingsObserver)
        }
    }

    /// Begins mirroring: subscribes to storage changes and settings changes, then does an
    /// initial sync. Call once at app launch.
    func start() {
        // Debounce live storage changes: the FE can write many times in quick succession (each
        // message, etc.) and reloading the widget on every write would exhaust the system reload
        // budget. Coalesce into one sync after activity settles; the app also syncs on
        // background/foreground (see AIChatService) so the home-screen widgets stay current.
        // Debounce on a background queue distinct from `queue` so `syncNow`'s `queue.sync` can't deadlock.
        cancellable = storage?.chatsPublisher()
            .debounce(for: liveUpdateDebounce, scheduler: DispatchQueue.global(qos: .utility))
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] _ in
                self?.syncNow()
            })

        // The same notification is posted when the global AI Chat toggle or the widget toggle
        // changes, so a single observer drives both the "re-sync" and "wipe" paths.
        settingsObserver = notificationCenter.addObserver(forName: .aiChatSettingsChanged,
                                                          object: nil,
                                                          queue: nil) { [weak self] _ in
            self?.syncNow()
        }

        syncNow()
    }

    /// Rebuilds the mirror from current storage (or wipes it when the gate is off). Safe to call
    /// repeatedly and from any thread.
    func syncNow() {
        queue.sync { self.performSync() }
    }

    /// Removes the entire mirror and reloads widgets. Used when the feature is turned off.
    func wipeWidgetData() {
        queue.sync {
            guard let dataLocation else { return }
            try? FileManager.default.removeItem(at: dataLocation.rootURL)
            reloadWidgets()
        }
    }

    // MARK: - Private

    private func performSync() {
        guard let storage, let dataLocation else { return }

        // Safety gate: if either the global AI Chat toggle or the widget toggle is off, the mirror
        // must not exist. `isAIChatRecentChatsWidgetUserSettingsEnabled` is AND-gated on the global flag.
        guard settings.isAIChatRecentChatsWidgetUserSettingsEnabled else {
            try? FileManager.default.removeItem(at: dataLocation.rootURL)
            reloadWidgets()
            return
        }

        Logger.duckAiWidget.notice("DUCKAI-WIDGET [app] writes to container=\(dataLocation.rootURL.path, privacy: .public)")

        do {
            let records = try storage.getAllChats()
            let allChats = records
                .compactMap { try? DuckAiChat.decode(from: $0.data).chat }
                .sorted { lhs, rhs in
                    // Pinned chats first, then most-recently edited — matches the in-app history order.
                    lhs.pinned == rhs.pinned ? lhs.lastEdit > rhs.lastEdit : lhs.pinned
                }
            let chats = allChats.prefix(Self.maxChats)

            logNativeStorageSnapshot(records: records, chats: allChats, storage: storage)

            let entries: [WidgetChatEntry] = chats.map { chat in
                WidgetChatEntry(chatId: chat.chatId,
                                title: chat.title,
                                lastEdit: chat.lastEdit,
                                isImageGeneration: chat.isImageGeneration,
                                pinned: chat.pinned)
            }

            // Ensure the mirror directory exists (it won't on a fresh install / after a wipe).
            try FileManager.default.createDirectory(at: dataLocation.rootURL, withIntermediateDirectories: true)

            let snapshot = WidgetChatSnapshot(totalChatCount: allChats.count, chats: entries)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: dataLocation.chatsFileURL, options: .atomic)

            syncImageGallery(from: allChats, storage: storage, location: dataLocation)

            reloadWidgets()
        } catch {
            Logger.duckAiWidget.error("DUCKAI-WIDGET [app] sync FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Builds the image gallery mirror: gallery-resolution JPEGs for the most recent generated
    /// images plus an `images.json` index, and removes images no longer in the set.
    private func syncImageGallery(from chats: [DuckAiChat],
                                  storage: DuckAiNativeObservableStorage,
                                  location: AIChatWidgetDataLocation) {
        do {
            try FileManager.default.createDirectory(at: location.galleryDirectoryURL, withIntermediateDirectories: true)

            var entries: [WidgetImageEntry] = []
            for chat in chats where chat.isImageGeneration {
                for fileRef in chat.fileRefs {
                    guard entries.count < Self.maxGalleryImages else { break }
                    if writeGalleryImage(imageId: fileRef, storage: storage, location: location) {
                        entries.append(WidgetImageEntry(imageId: fileRef, chatId: chat.chatId))
                    }
                }
                if entries.count >= Self.maxGalleryImages { break }
            }

            removeStaleGalleryImages(keeping: Set(entries.map(\.imageId)), location: location)

            let data = try JSONEncoder().encode(entries)
            try data.write(to: location.imagesFileURL, options: .atomic)

            let imagesExist = FileManager.default.fileExists(atPath: location.imagesFileURL.path)
            Logger.duckAiWidget.notice("DUCKAI-WIDGET [gallery] wrote \(entries.count, privacy: .public) entries → images.json exists=\(imagesExist, privacy: .public) at \(location.imagesFileURL.path, privacy: .public)")
        } catch {
            Logger.duckAiWidget.error("DUCKAI-WIDGET [gallery] sync FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Writes a gallery-resolution JPEG for an image id, reusing an existing one (images are
    /// immutable by UUID). Returns true when a usable file exists afterwards.
    private func writeGalleryImage(imageId: String,
                                   storage: DuckAiNativeObservableStorage,
                                   location: AIChatWidgetDataLocation) -> Bool {
        let destination = location.galleryImageURL(forImageId: imageId)
        if FileManager.default.fileExists(atPath: destination.path) {
            return true
        }
        guard let content = try? storage.getFile(uuid: imageId),
              let bytes = Self.decodedFileBytes(fromEnvelope: content.data),
              let image = UIImage(data: bytes),
              let jpeg = Self.downscaledJPEG(from: image, maxDimension: Self.galleryMaxDimension) else {
            return false
        }
        do {
            try jpeg.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func removeStaleGalleryImages(keeping ids: Set<String>, location: AIChatWidgetDataLocation) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: location.galleryDirectoryURL,
                                                               includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "jpg" {
            let imageId = file.deletingPathExtension().lastPathComponent
            if !ids.contains(imageId) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func logNativeStorageSnapshot(records: [DuckAiChatRecord],
                                          chats: [DuckAiChat],
                                          storage: DuckAiNativeObservableStorage) {
        let fileCount = (try? storage.listFiles().count) ?? -1
        let imageChats = chats.filter { $0.isImageGeneration }.count
        Logger.duckAiWidget.notice("DUCKAI-WIDGET [app] snapshot: \(records.count, privacy: .public) chats, \(imageChats, privacy: .public) image-gen, \(fileCount, privacy: .public) files in storage")
    }

    /// Native storage persists files as a JSON envelope — `{ chatId, mimeType, fileName, data }` —
    /// where `data` is the base64-encoded file contents (optionally wrapped in a `data:` URL), not
    /// raw image bytes. Returns the decoded raw bytes, or nil if the envelope can't be parsed.
    static func decodedFileBytes(fromEnvelope envelope: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
              let dataString = object["data"] as? String else {
            return nil
        }
        let base64: String
        if dataString.hasPrefix("data:"), let comma = dataString.firstIndex(of: ",") {
            base64 = String(dataString[dataString.index(after: comma)...])
        } else {
            base64 = dataString
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    /// Aspect-preserving downscale to fit within `maxDimension` (never upscales), encoded as JPEG.
    private static func downscaledJPEG(from image: UIImage, maxDimension: CGFloat) -> Data? {
        let longestEdge = max(image.size.width, image.size.height, 1)
        let scale = min(maxDimension / longestEdge, 1)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}
