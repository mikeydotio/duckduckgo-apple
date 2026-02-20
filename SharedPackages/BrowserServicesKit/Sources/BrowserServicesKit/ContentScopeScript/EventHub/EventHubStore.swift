//
//  EventHubStore.swift
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

/// Persisted state for a single telemetry entry.
public struct TelemetryPersistedState: Codable, Equatable {
    public let name: String
    public let periodStart: Date
    public let periodEnd: Date
    public let periodSeconds: Int
    public var parameters: [String: ParameterPersistedState]

    public init(name: String, periodStart: Date, periodEnd: Date, periodSeconds: Int, parameters: [String: ParameterPersistedState]) {
        self.name = name
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodSeconds = periodSeconds
        self.parameters = parameters
    }
}

/// Persisted state for a counter parameter.
public struct ParameterPersistedState: Codable, Equatable {
    public let template: String
    public var data: Int
    public let source: String
    public let buckets: [BucketConfig]
    public var stopCounting: Bool

    public init(template: String, data: Int, source: String, buckets: [BucketConfig], stopCounting: Bool) {
        self.template = template
        self.data = data
        self.source = source
        self.buckets = buckets
        self.stopCounting = stopCounting
    }
}

/// A single bucket definition for the counter parameter.
public struct BucketConfig: Codable, Equatable {
    public let minInclusive: Int
    public let maxExclusive: Int?
    public let name: String

    public init(minInclusive: Int, maxExclusive: Int?, name: String) {
        self.minInclusive = minInclusive
        self.maxExclusive = maxExclusive
        self.name = name
    }
}

/// Protocol for persisting eventHub telemetry state.
///
/// State must survive app closure and fire button operations.
public protocol EventHubStore {
    func loadAllTelemetryStates() -> [TelemetryPersistedState]
    func saveTelemetryState(_ state: TelemetryPersistedState)
    func removeTelemetryState(named: String)
    func removeAllTelemetryStates()
}

/// UserDefaults-based implementation of EventHubStore.
///
/// Uses a dedicated suite name to isolate eventHub data from the fire button
/// and other data clearing operations.
public final class UserDefaultsEventHubStore: EventHubStore {

    private static let suiteName = "com.duckduckgo.eventHub"
    private static let statesKey = "telemetryStates"

    private let defaults: UserDefaults

    public init() {
        self.defaults = UserDefaults(suiteName: UserDefaultsEventHubStore.suiteName) ?? UserDefaults.standard
    }

    /// Visible for testing.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadAllTelemetryStates() -> [TelemetryPersistedState] {
        guard let data = defaults.data(forKey: Self.statesKey) else { return [] }
        return (try? JSONDecoder().decode([TelemetryPersistedState].self, from: data)) ?? []
    }

    public func saveTelemetryState(_ state: TelemetryPersistedState) {
        var states = loadAllTelemetryStates().filter { $0.name != state.name }
        states.append(state)
        saveAll(states)
    }

    public func removeTelemetryState(named name: String) {
        let states = loadAllTelemetryStates().filter { $0.name != name }
        saveAll(states)
    }

    public func removeAllTelemetryStates() {
        defaults.removeObject(forKey: Self.statesKey)
    }

    private func saveAll(_ states: [TelemetryPersistedState]) {
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: Self.statesKey)
        }
    }
}
