//
//  MockSettingsStore.swift
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

@testable import DuckAILocalServerImpl

final class MockSettingsStore: DuckAISettingsStore, @unchecked Sendable {
    var settings: [String: String] = [:]
    var migrationDone = false

    func getAll() -> [String: String] { settings }
    func get(key: String) -> String? { settings[key] }
    func set(key: String, value: String) { settings[key] = value }
    func replaceAll(settings: [String: String]) { self.settings = settings }
    func delete(key: String) { settings.removeValue(forKey: key) }
    func deleteAll() { settings.removeAll() }
    var isMigrationDone: Bool { migrationDone }
    func setMigrationDone() { migrationDone = true }
}
