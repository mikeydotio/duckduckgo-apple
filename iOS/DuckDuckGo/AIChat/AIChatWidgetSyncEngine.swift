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

    /// How many of each kind the snapshot carries. The widget picks from this pool with its own
    /// per-family cap: large shows 6 rows total with ≤2 pinned, medium shows 3 with ≤1 pinned.
    /// Storing them separately (rather than a single pinned-first prefix) means a user with many
    /// pinned chats still gets recent unpinned ones in the snapshot.
    static let maxPinnedInSnapshot = 3
    static let maxRecentInSnapshot = 6
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

    /// Hash of the most recently written chats.json bytes, used to suppress no-op
    /// `WidgetCenter.reloadAllTimelines()` calls. iOS rate-limits the reload budget (~40/day per
    /// widget); pulse triggers (resume/suspend, settings observer, repeated FE saves with no chat
    /// change) would otherwise burn that budget and leave the on-screen widget stale.
    private var lastWrittenSnapshotHash: Int?

    init(storage: DuckAiNativeObservableStorage?,
         settings: AIChatSettingsProvider,
         dataLocation: AIChatWidgetDataLocation?,
         notificationCenter: NotificationCenter = .default,
         liveUpdateDebounce: DispatchQueue.SchedulerTimeType.Stride = .seconds(2),
         reloadWidgets: @escaping () -> Void = {
             // Targeted reloads instead of `reloadAllTimelines()`: the latter consumes the daily
             // reload budget for *every* widget the app exposes (search, favorites, VPN, lock-screen,
             // etc.). Once any one of those is hammered the whole pool is starved and on-screen
             // widgets freeze on the previous render. Reloading only the two AIChat widget kinds
             // keeps the chat/gallery widgets in their own budget bucket.
             DispatchQueue.main.async {
                 WidgetCenter.shared.reloadTimelines(ofKind: "AIChatRecentChatsWidget")
                 WidgetCenter.shared.reloadTimelines(ofKind: "AIChatImageGalleryWidget")
             }
         }) {
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
            lastWrittenSnapshotHash = nil
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
            lastWrittenSnapshotHash = nil
            reloadWidgets()
            return
        }

        do {
            let records = try storage.getAllChats()
            // Single pass: decode + sort by recency. Downstream code (chat snapshot pools, gallery
            // sync) all want most-recent first; pinned/unpinned filtering is layered on top.
            let chatsByRecency = records
                .compactMap { try? DuckAiChat.decode(from: $0.data).chat }
                .sorted { $0.lastEdit > $1.lastEdit }

            // Split pools by lastEdit-desc, separately. Snapshot carries top N pinned + top M
            // unpinned so the widget can apply its per-family pinned cap without the snapshot
            // having starved it of unpinned chats (e.g., a user with many pinned chats).
            let topPinned = chatsByRecency.filter(\.pinned).prefix(Self.maxPinnedInSnapshot)
            let topUnpinned = chatsByRecency.filter { !$0.pinned }.prefix(Self.maxRecentInSnapshot)

            logNativeStorageSnapshot(records: records, chats: chatsByRecency, storage: storage)

            // Pinned-first ordering preserves the user's request that pinned chats sit at the top
            // — the widget view re-orders/caps as needed.
            let entries: [WidgetChatEntry] = (Array(topPinned) + Array(topUnpinned)).map { chat in
                WidgetChatEntry(chatId: chat.chatId,
                                title: chat.title,
                                lastEdit: chat.lastEdit,
                                isImageGeneration: chat.isImageGeneration,
                                pinned: chat.pinned)
            }

            let snapshot = WidgetChatSnapshot(totalChatCount: chatsByRecency.count, chats: entries)
            let data = try JSONEncoder().encode(snapshot)
            // Hash only the *view-relevant* fields, in display order. The user typing inside one
            // existing chat updates that chat's `lastEdit` per save (sometimes many times a second)
            // without changing what the widget actually shows — same titles, same order, same icons.
            // Hashing the raw encoded JSON would treat each tick as a new snapshot and burn the
            // WidgetCenter reload budget for visually-identical updates. If `lastEdit` ticks
            // *enough* to reorder the top N, the (chatId, title, …) tuples shift position and the
            // hash naturally changes — so genuine ordering changes still trigger a reload.
            let snapshotHash = Self.viewRelevantHash(totalCount: chatsByRecency.count, entries: entries)
            let fileExists = FileManager.default.fileExists(atPath: dataLocation.chatsFileURL.path)

            // No-op pulse guard: lifecycle / settings notifications fire even when chats haven't
            // changed. Calling reloadAllTimelines on those would burn the iOS reload budget
            // (~40/day/widget) and starve real changes later — exactly the bug that surfaces as
            // "the widget shows stale data." Skip the write+reload when the snapshot is identical
            // to the previous one AND the file is still on disk; rewrite if the file is missing
            // (fresh install, wiped on toggle-off).
            if snapshotHash == lastWrittenSnapshotHash && fileExists {
                Logger.duckAiWidget.notice("DUCKAI-WIDGET [app] sync skipped: unchanged visible snapshot")
                return
            }

            Logger.duckAiWidget.notice("DUCKAI-WIDGET [app] writes to container=\(dataLocation.rootURL.path, privacy: .public)")

            // Ensure the mirror directory exists (it won't on a fresh install / after a wipe).
            try FileManager.default.createDirectory(at: dataLocation.rootURL, withIntermediateDirectories: true)
            try data.write(to: dataLocation.chatsFileURL, options: .atomic)
            lastWrittenSnapshotHash = snapshotHash

            syncImageGallery(from: chatsByRecency, storage: storage, location: dataLocation)

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

    /// Hash of the chat list using only the fields the widget actually renders, in display order.
    /// Excludes `lastEdit` because it ticks per-keystroke during a save without changing the visual
    /// output — but ordering *is* captured since the (chatId, title, pinned, isImageGeneration)
    /// tuples shift position when an edit reorders the top N.
    static func viewRelevantHash(totalCount: Int, entries: [WidgetChatEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(totalCount)
        for entry in entries {
            hasher.combine(entry.chatId)
            hasher.combine(entry.title)
            hasher.combine(entry.pinned)
            hasher.combine(entry.isImageGeneration)
        }
        return hasher.finalize()
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
