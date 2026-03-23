//
//  SettingsHandler.swift
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
import DuckAILocalServerAPI

final class SettingsHandler: DuckAIRequestHandler, @unchecked Sendable {
    let pathPrefix = "/settings"
    private let maxBodySize = 65_536
    private let store: DuckAISettingsStore

    init(store: DuckAISettingsStore) {
        self.store = store
    }

    func handle(method: String, uri: String, body: Data?) async -> DuckAIResponse {
        guard uri == pathPrefix || uri.hasPrefix(pathPrefix + "/") else {
            return DuckAIResponse(statusCode: 404)
        }

        if let body, body.count > maxBodySize {
            return DuckAIResponse(statusCode: 413)
        }

        let subpath = String(uri.dropFirst(pathPrefix.count))
        let key: String? = subpath.isEmpty ? nil : {
            let raw = String(subpath.dropFirst())
            return raw.removingPercentEncoding ?? raw
        }()

        switch (method, key) {
        case ("GET", nil):
            return getAllSettings()
        case ("GET", let k?):
            return getSetting(key: k)
        case ("PUT", nil):
            return putAllSettings(body: body)
        case ("PUT", let k?):
            return putSetting(key: k, body: body)
        case ("DELETE", nil):
            return deleteAllSettings()
        case ("DELETE", let k?):
            return deleteSetting(key: k)
        default:
            return DuckAIResponse(statusCode: 405)
        }
    }

    private func getAllSettings() -> DuckAIResponse {
        let all = store.getAll()
        guard let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) else {
            return DuckAIResponse(statusCode: 500)
        }
        return DuckAIResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private func getSetting(key: String) -> DuckAIResponse {
        guard let value = store.get(key: key) else {
            return DuckAIResponse(statusCode: 404)
        }
        guard let encoded = try? JSONEncoder().encode(value) else {
            return DuckAIResponse(statusCode: 500)
        }
        return DuckAIResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: encoded)
    }

    private func putSetting(key: String, body: Data?) -> DuckAIResponse {
        guard let body,
              let value = try? JSONDecoder().decode(String.self, from: body) else {
            return DuckAIResponse(statusCode: 400)
        }
        store.set(key: key, value: value)
        return DuckAIResponse(statusCode: 204)
    }

    private func putAllSettings(body: Data?) -> DuckAIResponse {
        guard let body,
              let dict = try? JSONSerialization.jsonObject(with: body) as? [String: String] else {
            return DuckAIResponse(statusCode: 400)
        }
        store.replaceAll(settings: dict)
        return DuckAIResponse(statusCode: 204)
    }

    private func deleteSetting(key: String) -> DuckAIResponse {
        store.delete(key: key)
        return DuckAIResponse(statusCode: 204)
    }

    private func deleteAllSettings() -> DuckAIResponse {
        store.deleteAll()
        return DuckAIResponse(statusCode: 204)
    }
}
