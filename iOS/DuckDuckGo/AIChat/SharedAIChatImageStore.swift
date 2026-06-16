//
//  SharedAIChatImageStore.swift
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
import Core

/// Hand-off for an image shared into the app via the "Ask Duck.ai" share extension.
///
/// The extension writes the image bytes into the shared App Group container and opens the app with
/// `ddgOpenAIChat://?image=<token>`; the app reads (and removes) the bytes here. Both sides resolve
/// the same `<group-id-prefix>.app-configuration` App Group: the app via `Global`, the extension by
/// reading the `DuckDuckGoGroupIdentifierPrefix` Info.plist key (so it needs no link to this module).
enum SharedAIChatImageStore {

    static var appGroup: String { Global.appConfigurationGroupName }
    static let directoryName = "AskDuckAiSharedImages"

    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Reads and deletes the image bytes for `token`. Returns `nil` for an unknown or malformed token.
    static func loadAndRemove(token: String) -> Data? {
        Swift.print("[ASKDUCKAI] SharedAIChatImageStore.loadAndRemove token=\(token) group=\(appGroup) dir=\(directory?.path ?? "nil")")
        // The token comes from a deep link, so validate it is a plain UUID to prevent path traversal.
        guard UUID(uuidString: token) != nil, let url = directory?.appendingPathComponent(token) else {
            Swift.print("[ASKDUCKAI] loadAndRemove ABORT — invalid token or nil App Group container (entitlement missing?)")
            return nil
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try? Data(contentsOf: url)
        Swift.print("[ASKDUCKAI] loadAndRemove fileExists=\(exists) bytes=\(data?.count ?? -1) path=\(url.path)")
        return data
    }
}
