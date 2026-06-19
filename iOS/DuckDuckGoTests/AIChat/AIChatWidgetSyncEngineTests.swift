//
//  AIChatWidgetSyncEngineTests.swift
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

import XCTest
import Combine
import UIKit
import Core
import AIChat
import DuckAiDataStore
@testable import DuckDuckGo

final class AIChatWidgetSyncEngineTests: XCTestCase {

    // MARK: - Test double

    final class MockObservableStorage: DuckAiNativeStorageHandling, DuckAiNativeChatsObserving {
        var chats: [DuckAiChatRecord] = []
        var files: [String: Data] = [:]   // uuid -> bytes
        private let subject = CurrentValueSubject<[DuckAiChatRecord], Error>([])

        func emit() { subject.send(chats) }
        func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error> { subject.eraseToAnyPublisher() }

        // Chats
        func putChat(chatId: String, data: Data) throws {}
        func putChats(_ chats: [DuckAiChatRecord]) throws {}
        func getChat(chatId: String) throws -> DuckAiChatRecord? { chats.first { $0.chatId == chatId } }
        func getAllChats() throws -> [DuckAiChatRecord] { chats }
        func deleteChat(chatId: String) throws {}
        func deleteAllChats() throws {}

        // Files
        func putFile(uuid: String, chatId: String, data: Data) throws {}
        func getFile(uuid: String) throws -> DuckAiFileContent? {
            files[uuid].map { DuckAiFileContent(uuid: uuid, chatId: "", data: $0) }
        }
        func listFiles() throws -> [DuckAiFileMetadata] { [] }
        func deleteFile(uuid: String) throws {}
        func deleteFiles(chatId: String) throws {}
        func deleteAllFiles() throws {}

        // Entries
        func putEntry(key: String, value: Any) throws {}
        func getEntry(key: String) throws -> Any? { nil }
        func getAllEntries() throws -> [String: Any] { [:] }
        func deleteEntry(key: String) throws {}
        func deleteAllEntries() throws {}
        func replaceAllEntries(_ entries: [String: Any]) throws {}

        // Migration
        func isMigrationDone() throws -> Bool { true }
        func isMigrationDone(key: String) throws -> Bool { true }
        func markMigrationDone(key: String) throws {}
    }

    // MARK: - Helpers

    private func chatData(id: String, title: String, lastEdit: String, pinned: Bool = false) -> Data {
        let json = """
        { "chatId": "\(id)", "title": "\(title)", "model": "gpt", "lastEdit": "\(lastEdit)", "pinned": \(pinned), "messages": [] }
        """
        return Data(json.utf8)
    }

    private func imageGenChatData(id: String, lastEdit: String, fileRef: String) -> Data {
        let json = """
        { "chatId": "\(id)", "title": "Image chat", "model": "gpt", "lastEdit": "\(lastEdit)", "pinned": false,
          "fileRefs": ["\(fileRef)"],
          "messages": [ { "role": "assistant", "parts": [ { "type": "ui-component", "name": "generate-image" } ] } ] }
        """
        return Data(json.utf8)
    }

    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    /// Mirrors how native storage actually persists files: a JSON envelope with base64 `data`.
    private func makeImageEnvelope() -> Data {
        let base64 = makeJPEGData().base64EncodedString()
        let json = "{ \"chatId\": \"x\", \"mimeType\": \"image/jpeg\", \"fileName\": \"img.jpeg\", \"data\": \"\(base64)\" }"
        return Data(json.utf8)
    }

    private func makeLocation() -> AIChatWidgetDataLocation {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AIChatWidgetDataLocation(containerURL: dir)
    }

    private func readSnapshot(_ location: AIChatWidgetDataLocation) throws -> WidgetChatSnapshot {
        let data = try Data(contentsOf: location.chatsFileURL)
        return try JSONDecoder().decode(WidgetChatSnapshot.self, from: data)
    }

    private func readEntries(_ location: AIChatWidgetDataLocation) throws -> [WidgetChatEntry] {
        try readSnapshot(location).chats
    }

    private func makeEngine(storage: MockObservableStorage,
                            location: AIChatWidgetDataLocation,
                            widgetEnabled: Bool = true,
                            notificationCenter: NotificationCenter = NotificationCenter(),
                            reloadWidgets: @escaping () -> Void = {}) -> AIChatWidgetSyncEngine {
        let settings = MockAIChatSettingsProvider()
        settings.isAIChatRecentChatsWidgetUserSettingsEnabled = widgetEnabled
        return AIChatWidgetSyncEngine(storage: storage,
                                      settings: settings,
                                      dataLocation: location,
                                      notificationCenter: notificationCenter,
                                      liveUpdateDebounce: .seconds(0),
                                      reloadWidgets: reloadWidgets)
    }

    // MARK: - Mirror write (Task 4)

    func testWhenSyncNowThenMirrorWrittenSortedByLastEditDescending() throws {
        let storage = MockObservableStorage()
        storage.chats = [
            DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "Older", lastEdit: "2026-01-01T00:00:00.000Z")),
            DuckAiChatRecord(chatId: "b", data: chatData(id: "b", title: "Newer", lastEdit: "2026-02-01T00:00:00.000Z"))
        ]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let entries = try readEntries(location)
        XCTAssertEqual(entries.map(\.chatId), ["b", "a"])
        XCTAssertEqual(entries.first?.title, "Newer")
    }

    func testWhenChatPinnedThenSortsAboveNewerUnpinnedChat() throws {
        let storage = MockObservableStorage()
        storage.chats = [
            DuckAiChatRecord(chatId: "newer", data: chatData(id: "newer", title: "Newer", lastEdit: "2026-09-01T00:00:00.000Z")),
            DuckAiChatRecord(chatId: "pinnedOld", data: chatData(id: "pinnedOld", title: "Pinned", lastEdit: "2026-01-01T00:00:00.000Z", pinned: true))
        ]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let entries = try readEntries(location)
        XCTAssertEqual(entries.map(\.chatId), ["pinnedOld", "newer"])
        XCTAssertEqual(entries.first?.pinned, true)
    }

    func testWhenMoreThanSixChatsThenOnlyTopSixWritten() throws {
        let storage = MockObservableStorage()
        storage.chats = (0..<10).map { index in
            let day = String(format: "%02d", index + 1)
            return DuckAiChatRecord(chatId: "c\(index)", data: chatData(id: "c\(index)", title: "T\(index)", lastEdit: "2026-03-\(day)T00:00:00.000Z"))
        }
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let entries = try readEntries(location)
        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries.first?.chatId, "c9")
    }

    func testWhenMoreThanSixChatsThenSnapshotTotalReflectsAllChats() throws {
        let storage = MockObservableStorage()
        storage.chats = (0..<10).map { index in
            let day = String(format: "%02d", index + 1)
            return DuckAiChatRecord(chatId: "c\(index)", data: chatData(id: "c\(index)", title: "T\(index)", lastEdit: "2026-03-\(day)T00:00:00.000Z"))
        }
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let snapshot = try readSnapshot(location)
        XCTAssertEqual(snapshot.totalChatCount, 10)
        XCTAssertEqual(snapshot.chats.count, 6)
    }

    // MARK: - Image-generation flag

    func testWhenImageGenChatThenEntryFlaggedAsImageGeneration() throws {
        let storage = MockObservableStorage()
        storage.chats = [
            DuckAiChatRecord(chatId: "img", data: imageGenChatData(id: "img", lastEdit: "2026-05-02T00:00:00.000Z", fileRef: "file-1")),
            DuckAiChatRecord(chatId: "txt", data: chatData(id: "txt", title: "Text", lastEdit: "2026-05-01T00:00:00.000Z"))
        ]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let entries = try readEntries(location)
        XCTAssertEqual(entries.first(where: { $0.chatId == "img" })?.isImageGeneration, true)
        XCTAssertEqual(entries.first(where: { $0.chatId == "txt" })?.isImageGeneration, false)
    }

    // MARK: - File envelope decoding

    func testWhenEnvelopeHasPlainBase64ThenBytesDecoded() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let envelope = Data("{ \"data\": \"\(payload.base64EncodedString())\" }".utf8)
        XCTAssertEqual(AIChatWidgetSyncEngine.decodedFileBytes(fromEnvelope: envelope), payload)
    }

    func testWhenEnvelopeHasDataURLThenBytesDecoded() {
        let payload = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let envelope = Data("{ \"data\": \"data:image/jpeg;base64,\(payload.base64EncodedString())\" }".utf8)
        XCTAssertEqual(AIChatWidgetSyncEngine.decodedFileBytes(fromEnvelope: envelope), payload)
    }

    func testWhenEnvelopeIsNotJSONThenNil() {
        XCTAssertNil(AIChatWidgetSyncEngine.decodedFileBytes(fromEnvelope: Data([0xFF, 0xD8, 0xFF])))
    }

    func testWhenEnvelopeMissingDataFieldThenNil() {
        XCTAssertNil(AIChatWidgetSyncEngine.decodedFileBytes(fromEnvelope: Data("{ \"mimeType\": \"image/jpeg\" }".utf8)))
    }

    // MARK: - Image gallery

    private func readImages(_ location: AIChatWidgetDataLocation) throws -> [WidgetImageEntry] {
        let data = try Data(contentsOf: location.imagesFileURL)
        return try JSONDecoder().decode([WidgetImageEntry].self, from: data)
    }

    func testWhenImageGenChatsThenGalleryWritten() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "img", data: imageGenChatData(id: "img", lastEdit: "2026-05-01T00:00:00.000Z", fileRef: "file-1"))]
        storage.files = ["file-1": makeImageEnvelope()]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let images = try readImages(location)
        XCTAssertEqual(images.map(\.imageId), ["file-1"])
        XCTAssertEqual(images.first?.chatId, "img")
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.galleryImageURL(forImageId: "file-1").path))
    }

    func testWhenImageNoLongerPresentThenStaleGalleryImageRemoved() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "img", data: imageGenChatData(id: "img", lastEdit: "2026-05-01T00:00:00.000Z", fileRef: "file-1"))]
        storage.files = ["file-1": makeImageEnvelope()]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.galleryImageURL(forImageId: "file-1").path))

        storage.chats = [DuckAiChatRecord(chatId: "img", data: chatData(id: "img", title: "Now text", lastEdit: "2026-05-02T00:00:00.000Z"))]
        engine.syncNow()

        XCTAssertFalse(FileManager.default.fileExists(atPath: location.galleryImageURL(forImageId: "file-1").path))
        XCTAssertEqual(try readImages(location).count, 0)
    }

    // MARK: - Gating + subscription (Task 6)

    func testWhenSettingDisabledThenSyncWipesInsteadOfWriting() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "X", lastEdit: "2026-01-01T00:00:00.000Z"))]
        let location = makeLocation()

        let settings = MockAIChatSettingsProvider()
        settings.isAIChatRecentChatsWidgetUserSettingsEnabled = true
        let engine = AIChatWidgetSyncEngine(storage: storage, settings: settings, dataLocation: location, reloadWidgets: {})

        engine.syncNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.chatsFileURL.path))

        settings.isAIChatRecentChatsWidgetUserSettingsEnabled = false
        engine.syncNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.rootURL.path))
    }

    func testWhenStorageEmitsThenMirrorUpdates() {
        let storage = MockObservableStorage()
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.start()
        storage.chats = [DuckAiChatRecord(chatId: "z", data: chatData(id: "z", title: "Z", lastEdit: "2026-06-01T00:00:00.000Z"))]
        storage.emit()

        // The live path debounces + syncs on a background queue, so poll for the result.
        let synced = expectation(description: "mirror updated from storage emission")
        DispatchQueue.global().async {
            for _ in 0..<60 {
                if let entries = try? self.readEntries(location), entries.map(\.chatId) == ["z"] {
                    synced.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        wait(for: [synced], timeout: 5)
    }

    func testWhenWipeWidgetDataThenMirrorRemoved() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "X", lastEdit: "2026-01-01T00:00:00.000Z"))]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.chatsFileURL.path))

        engine.wipeWidgetData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.rootURL.path))
    }

    // MARK: - Reload deduping (protects WidgetCenter's daily reload budget)

    func testWhenSyncCalledRepeatedlyWithSameChatsThenReloadFiresOnce() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "X", lastEdit: "2026-01-01T00:00:00.000Z"))]
        let location = makeLocation()
        var reloads = 0
        let engine = makeEngine(storage: storage, location: location, reloadWidgets: { reloads += 1 })

        engine.syncNow()
        engine.syncNow()
        engine.syncNow()

        XCTAssertEqual(reloads, 1, "Pulses with identical snapshots must not consume the WidgetCenter reload budget")
    }

    func testWhenSnapshotChangesThenReloadFiresAgain() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "X", lastEdit: "2026-01-01T00:00:00.000Z"))]
        let location = makeLocation()
        var reloads = 0
        let engine = makeEngine(storage: storage, location: location, reloadWidgets: { reloads += 1 })

        engine.syncNow()                                  // initial write → 1
        engine.syncNow()                                  // same data → suppressed
        storage.chats.append(DuckAiChatRecord(chatId: "b", data: chatData(id: "b", title: "Y", lastEdit: "2026-02-01T00:00:00.000Z")))
        engine.syncNow()                                  // new chat → 2

        XCTAssertEqual(reloads, 2)
    }

    func testWhenMirrorFileMissingThenSyncRewritesEvenWhenSnapshotUnchanged() throws {
        let storage = MockObservableStorage()
        storage.chats = [DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "X", lastEdit: "2026-01-01T00:00:00.000Z"))]
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()
        try FileManager.default.removeItem(at: location.chatsFileURL)
        engine.syncNow()

        XCTAssertTrue(FileManager.default.fileExists(atPath: location.chatsFileURL.path),
                      "When the mirror file disappears (e.g. user wiped data), the next sync must rewrite it even if in-memory snapshot is unchanged")
    }

    func testWhenLastEditTicksWithoutChangingOrderThenReloadSuppressed() throws {
        // Simulates: user types in chat "a" → FE saves repeatedly with new lastEdit per save.
        // Nothing the widget displays (title/pinned/icon/position) changes, so the dedupe
        // should suppress these no-op reloads to preserve the iOS reload budget.
        let storage = MockObservableStorage()
        storage.chats = [
            DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "Active chat", lastEdit: "2026-02-01T00:00:00.000Z")),
            DuckAiChatRecord(chatId: "b", data: chatData(id: "b", title: "Older",       lastEdit: "2026-01-01T00:00:00.000Z"))
        ]
        let location = makeLocation()
        var reloads = 0
        let engine = makeEngine(storage: storage, location: location, reloadWidgets: { reloads += 1 })

        engine.syncNow()                                                                                      // initial → 1
        storage.chats[0] = DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "Active chat",
                                                                        lastEdit: "2026-02-01T00:00:01.000Z")) // typing tick
        engine.syncNow()                                                                                      // visible unchanged → suppressed
        storage.chats[0] = DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "Active chat",
                                                                        lastEdit: "2026-02-01T00:00:02.000Z")) // another tick
        engine.syncNow()                                                                                      // visible unchanged → suppressed

        XCTAssertEqual(reloads, 1)
    }

    // MARK: - Pinned-first ordering (pinned chats always at top regardless of edit date)

    func testWhenManyPinnedThenAllSnapshotSlotsCanBePinned() throws {
        // User preference: pinned chats always sit on top of the widget regardless of edit date.
        // If a user has 6+ pinned chats, the entire widget can be filled with pinned rows — even
        // when fresher unpinned chats exist. Recents only appear when pinned doesn't fill the cap.
        let storage = MockObservableStorage()
        let pinned = (0..<7).map { idx in
            let day = String(format: "%02d", idx + 1)
            return DuckAiChatRecord(chatId: "p\(idx)",
                                    data: chatData(id: "p\(idx)", title: "Pinned \(idx)",
                                                   lastEdit: "2026-01-\(day)T00:00:00.000Z",
                                                   pinned: true))
        }
        let recent = (0..<3).map { idx in
            let day = String(format: "%02d", idx + 1)
            return DuckAiChatRecord(chatId: "r\(idx)",
                                    data: chatData(id: "r\(idx)", title: "Recent \(idx)",
                                                   lastEdit: "2026-02-\(day)T00:00:00.000Z"))
        }
        storage.chats = pinned + recent
        let location = makeLocation()
        let engine = makeEngine(storage: storage, location: location)

        engine.syncNow()

        let entries = try readEntries(location)
        XCTAssertEqual(entries.count, AIChatWidgetSyncEngine.maxChats)
        XCTAssertTrue(entries.allSatisfy(\.pinned),
                      "When the user has more pinned chats than the widget can show, the snapshot is all pinned — fresher unpinned chats wait their turn")
    }

    func testWhenLastEditTicksAndChangesTopOrderThenReloadFires() throws {
        // If a tick actually reorders the top N (chat "b" overtakes "a"), the widget shows different
        // content and the reload must fire. This is the case that must NOT be suppressed.
        let storage = MockObservableStorage()
        storage.chats = [
            DuckAiChatRecord(chatId: "a", data: chatData(id: "a", title: "First",  lastEdit: "2026-02-01T00:00:00.000Z")),
            DuckAiChatRecord(chatId: "b", data: chatData(id: "b", title: "Second", lastEdit: "2026-01-01T00:00:00.000Z"))
        ]
        let location = makeLocation()
        var reloads = 0
        let engine = makeEngine(storage: storage, location: location, reloadWidgets: { reloads += 1 })

        engine.syncNow()  // initial: order is [a, b] → 1 reload
        storage.chats[1] = DuckAiChatRecord(chatId: "b", data: chatData(id: "b", title: "Second",
                                                                        lastEdit: "2026-03-01T00:00:00.000Z"))
        engine.syncNow()  // now order is [b, a] → must reload → 2

        XCTAssertEqual(reloads, 2)
    }
}
