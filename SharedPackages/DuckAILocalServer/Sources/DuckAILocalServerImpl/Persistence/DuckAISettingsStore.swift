//
//  DuckAISettingsStore.swift
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

protocol DuckAISettingsStore: Sendable {
    func getAll() -> [String: String]
    func get(key: String) -> String?
    func set(key: String, value: String)
    func replaceAll(settings: [String: String])
    func delete(key: String)
    func deleteAll()

    var isMigrationDone: Bool { get }
    func setMigrationDone()
}

final class UserDefaultsDuckAISettingsStore: DuckAISettingsStore, @unchecked Sendable {
    private static let settingsKey = "com.duckduckgo.aichat.localserver.settings"
    private static let migrationKey = "com.duckduckgo.aichat.localserver.migrationDone"

    private let userDefaults: UserDefaults
    private let lock = NSLock()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func getAll() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.dictionary(forKey: Self.settingsKey) as? [String: String] ?? [:]
    }

    func get(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let dict = userDefaults.dictionary(forKey: Self.settingsKey) as? [String: String] ?? [:]
        return dict[key]
    }

    func set(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        var dict = userDefaults.dictionary(forKey: Self.settingsKey) as? [String: String] ?? [:]
        dict[key] = value
        userDefaults.set(dict, forKey: Self.settingsKey)
    }

    func replaceAll(settings: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.set(settings, forKey: Self.settingsKey)
    }

    func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        var dict = userDefaults.dictionary(forKey: Self.settingsKey) as? [String: String] ?? [:]
        dict.removeValue(forKey: key)
        userDefaults.set(dict, forKey: Self.settingsKey)
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.removeObject(forKey: Self.settingsKey)
    }

    var isMigrationDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.bool(forKey: Self.migrationKey)
    }

    func setMigrationDone() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.set(true, forKey: Self.migrationKey)
    }
}
