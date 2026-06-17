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

    /// Longest edge of a generated-image thumbnail, in points.
    private static let thumbnailMaxDimension: CGFloat = 100

    private let storage: DuckAiNativeObservableStorage?
    private let settings: AIChatSettingsProvider
    private let dataLocation: AIChatWidgetDataLocation?
    private let notificationCenter: NotificationCenter
    private let reloadWidgets: () -> Void
    private let queue = DispatchQueue(label: "com.duckduckgo.aichat.widget.sync")

    private var cancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?

    init(storage: DuckAiNativeObservableStorage?,
         settings: AIChatSettingsProvider,
         dataLocation: AIChatWidgetDataLocation?,
         notificationCenter: NotificationCenter = .default,
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.storage = storage
        self.settings = settings
        self.dataLocation = dataLocation
        self.notificationCenter = notificationCenter
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
        cancellable = storage?.chatsPublisher()
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

        do {
            let records = try storage.getAllChats()
            let allChats = records
                .compactMap { try? DuckAiChat.decode(from: $0.data).chat }
                .sorted { $0.lastEdit > $1.lastEdit }
            let chats = allChats.prefix(Self.maxChats)

            logNativeStorageSnapshot(records: records, chats: allChats, storage: storage)

            try FileManager.default.createDirectory(at: dataLocation.thumbnailsDirectoryURL, withIntermediateDirectories: true)

            var keptThumbnailIds = Set<String>()
            let entries: [WidgetChatEntry] = chats.map { chat in
                var hasThumbnail = false
                if chat.isImageGeneration, let ref = chat.fileRefs.first {
                    hasThumbnail = writeThumbnail(forChatId: chat.chatId, fileRef: ref, storage: storage, location: dataLocation)
                    if hasThumbnail { keptThumbnailIds.insert(chat.chatId) }
                }
                return WidgetChatEntry(chatId: chat.chatId,
                                       title: chat.title,
                                       lastEdit: chat.lastEdit,
                                       hasImageThumbnail: hasThumbnail)
            }

            removeStaleThumbnails(keeping: keptThumbnailIds, location: dataLocation)

            let snapshot = WidgetChatSnapshot(totalChatCount: allChats.count, chats: entries)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: dataLocation.chatsFileURL, options: .atomic)
            reloadWidgets()
        } catch {
            Logger.aiChat.error("[Widget] sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// DEBUG-only diagnostics. Leads with the short, high-signal lines (file inventory + per-fileRef
    /// `getFile` results) because Xcode's console drops large/rapid output; the bulky raw chat JSON
    /// is written to a file whose path is printed, so it can be opened and copied in full.
    /// Compiled out of release.
    private func logNativeStorageSnapshot(records: [DuckAiChatRecord],
                                          chats: [DuckAiChat],
                                          storage: DuckAiNativeObservableStorage) {
        #if DEBUG
        print("DUCKAI-WIDGET ===== snapshot: \(records.count) chats =====")

        // 1) File inventory — the key question is whether image bytes exist in native storage at all.
        if let files = try? storage.listFiles() {
            print("DUCKAI-WIDGET [files] count=\(files.count)")
            for file in files {
                print("DUCKAI-WIDGET [file] uuid=\(file.uuid) chatId=\(file.chatId) size=\(file.dataSize)")
            }
        } else {
            print("DUCKAI-WIDGET [files] listFiles() threw")
        }

        // 2) Per-chat fileRefs + what getFile actually returns for each.
        for chat in chats {
            print("DUCKAI-WIDGET [chat] \(chat.chatId) imageGen=\(chat.isImageGeneration) fileRefs=\(chat.fileRefs)")
            for ref in chat.fileRefs {
                if let file = try? storage.getFile(uuid: ref) {
                    let bytes = Self.decodedFileBytes(fromEnvelope: file.data)
                    let decodes = bytes.flatMap { UIImage(data: $0) } != nil
                    print("DUCKAI-WIDGET   [getFile \(ref)] envelope=\(file.data.count)B decoded=\(bytes?.count ?? 0)B UIImage=\(decodes)")
                } else {
                    print("DUCKAI-WIDGET   [getFile \(ref)] nil")
                }
            }
        }

        // 3) Full raw chat JSON → a file (console truncates large prints).
        let dump = records
            .map { "// chat \($0.chatId)\n" + (String(data: $0.data, encoding: .utf8) ?? "<non-utf8 \($0.data.count) bytes>") }
            .joined(separator: "\n\n")
        let dumpURL = FileManager.default.temporaryDirectory.appendingPathComponent("duck-ai-widget-chats-dump.json")
        try? dump.data(using: .utf8)?.write(to: dumpURL)
        print("DUCKAI-WIDGET [dump] full chat JSON → \(dumpURL.path)")
        print("DUCKAI-WIDGET ===== end snapshot =====")
        #endif
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

    /// Writes a downscaled JPEG thumbnail for an image-generation chat. Best-effort: any failure
    /// returns false so the row renders title-only.
    private func writeThumbnail(forChatId chatId: String,
                                fileRef: String,
                                storage: DuckAiNativeObservableStorage,
                                location: AIChatWidgetDataLocation) -> Bool {
        guard let content = try? storage.getFile(uuid: fileRef),
              let bytes = Self.decodedFileBytes(fromEnvelope: content.data),
              let image = UIImage(data: bytes) else {
            #if DEBUG
            print("[DUCK.AI WIDGET] thumbnail FAILED for chat \(chatId) fileRef \(fileRef): envelope decode or UIImage init returned nil")
            #endif
            return false
        }

        let longestEdge = max(image.size.width, image.size.height, 1)
        let scale = min(Self.thumbnailMaxDimension / longestEdge, 1)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpeg = scaled.jpegData(compressionQuality: 0.7) else { return false }
        do {
            try jpeg.write(to: location.thumbnailURL(forChatId: chatId), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func removeStaleThumbnails(keeping ids: Set<String>, location: AIChatWidgetDataLocation) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: location.thumbnailsDirectoryURL,
                                                               includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "jpg" {
            let chatId = file.deletingPathExtension().lastPathComponent
            if !ids.contains(chatId) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
