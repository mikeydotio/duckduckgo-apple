//
//  EventHub.swift
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

import Combine
import Foundation
import PrivacyConfig

/// Manages eventHub telemetry: receives web events from C-S-S, maintains counters,
/// schedules pixel firing, and persists state across app sessions.
///
/// The eventHub feature MUST NOT be disabled due to privacy protections being disabled.
/// The ONLY way to disable it is through an explicit disabled state (or feature absent)
/// in the remote configuration.
public final class EventHub {

    private let privacyConfigManager: PrivacyConfigurationManaging
    private let pixelFiring: EventHubPixelFiring
    private let store: EventHubStore
    private let dateProvider: () -> Date

    private var telemetryMap: [String: TelemetryEntry] = [:]
    private var timers: [String: Timer] = [:]

    /// Tracks seen event types per webView to deduplicate events per page.
    /// Uses NSMapTable with weak keys to avoid retaining WKWebView instances.
    private var seenEventsPerWebView: [ObjectIdentifier: Set<String>] = [:]

    private var configCancellable: AnyCancellable?

    /// The current raw config dictionary for the eventHub feature.
    /// Updated on each config change; running telemetry reads it when their cycle ends.
    private var currentConfig: [String: Any]?

    public init(privacyConfigManager: PrivacyConfigurationManaging,
                pixelFiring: EventHubPixelFiring,
                store: EventHubStore,
                dateProvider: @escaping () -> Date = { Date() }) {
        self.privacyConfigManager = privacyConfigManager
        self.pixelFiring = pixelFiring
        self.store = store
        self.dateProvider = dateProvider

        restorePersistedState()
        onConfigChanged()

        configCancellable = privacyConfigManager.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.onConfigChanged()
            }
    }

    // MARK: - Config Handling

    /// Called when the remote config changes.
    /// Only client-level enabled/disabled state is considered (NOT page-level).
    public func onConfigChanged() {
        let config = privacyConfigManager.privacyConfig
        let featureSettings = config.settings(for: .eventHub)

        // Store the latest config — running telemetry reads it at cycle end
        currentConfig = featureSettings

        guard isEnabled(config: config) else {
            onDisable()
            return
        }

        // Initialise any new telemetry (existing ones pick up config changes at next cycle end)
        guard let telemetryConfig = featureSettings["telemetry"] as? [String: [String: Any]] else { return }

        for name in telemetryConfig.keys {
            registerTelemetry(name: name, telemetryConfig: telemetryConfig)
        }
    }

    func isEnabled(config: PrivacyConfiguration? = nil) -> Bool {
        let privConfig = config ?? privacyConfigManager.privacyConfig
        return privConfig.isEnabled(featureKey: .eventHub, versionProvider: AppVersionProvider(), defaultValue: false)
    }

    // MARK: - Telemetry Registration

    private func registerTelemetry(name: String, telemetryConfig: [String: [String: Any]]) {
        guard isEnabled() else { return }
        guard let pixelConfig = telemetryConfig[name] else { return }
        guard telemetryMap[name] == nil else { return }

        // Check if this telemetry is enabled
        guard let state = pixelConfig["state"] as? String, state == "enabled" else { return }

        guard let entry = TelemetryEntry(name: name, config: pixelConfig, dateProvider: dateProvider) else { return }

        telemetryMap[name] = entry
        entry.start()
        store.saveTelemetryState(entry.persistedState)
        scheduleFireTelemetry(at: entry.periodEnd, telemetryName: name)
    }

    private func deregisterTelemetry(name: String) {
        guard telemetryMap[name] != nil else { return }
        timers[name]?.invalidate()
        timers.removeValue(forKey: name)
        telemetryMap.removeValue(forKey: name)
        store.removeTelemetryState(named: name)
    }

    private func onDisable() {
        for name in Array(timers.keys) {
            timers[name]?.invalidate()
        }
        timers.removeAll()

        for name in Array(telemetryMap.keys) {
            deregisterTelemetry(name: name)
        }
    }

    // MARK: - Timer Scheduling

    private func scheduleFireTelemetry(at fireDate: Date, telemetryName: String) {
        guard timers[telemetryName] == nil else { return }
        guard telemetryMap[telemetryName] != nil else { return }

        let now = dateProvider()
        let delay = max(fireDate.timeIntervalSince(now), 0)

        if delay <= 0 {
            // Fire immediately
            fireTelemetry(telemetryName: telemetryName)
        } else {
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.fireTelemetry(telemetryName: telemetryName)
            }
            timers[telemetryName] = timer
        }
    }

    private func fireTelemetry(telemetryName: String) {
        guard isEnabled() else { return }
        guard let entry = telemetryMap[telemetryName] else { return }

        timers[telemetryName]?.invalidate()
        timers.removeValue(forKey: telemetryName)

        entry.fire(pixelFiring: pixelFiring)

        // Re-register with latest config (applies any config changes)
        deregisterTelemetry(name: telemetryName)

        if let telemetryConfig = currentConfig?["telemetry"] as? [String: [String: Any]] {
            registerTelemetry(name: telemetryName, telemetryConfig: telemetryConfig)
        }
    }

    // MARK: - Event Handling

    /// Process a webEvent from C-S-S.
    /// Events are deduplicated per webView (tab) per page navigation.
    public func handleWebEvent(type: String, webViewIdentifier: ObjectIdentifier) {
        guard isEnabled() else { return }

        // Deduplicate: only count one event of each type per page per tab
        var seenSet = seenEventsPerWebView[webViewIdentifier] ?? Set()
        if seenSet.contains(type) { return }
        seenSet.insert(type)
        seenEventsPerWebView[webViewIdentifier] = seenSet

        for entry in telemetryMap.values {
            entry.handleEvent(type: type)
            store.saveTelemetryState(entry.persistedState)
        }
    }

    /// Reset deduplication state for a webView (call on navigation).
    public func resetDeduplication(for webViewIdentifier: ObjectIdentifier) {
        seenEventsPerWebView.removeValue(forKey: webViewIdentifier)
    }

    /// Remove deduplication tracking for a webView (call when webView is deallocated).
    public func removeWebView(_ webViewIdentifier: ObjectIdentifier) {
        seenEventsPerWebView.removeValue(forKey: webViewIdentifier)
    }

    // MARK: - Persistence

    private func restorePersistedState() {
        let savedStates = store.loadAllTelemetryStates()
        let now = dateProvider()

        for state in savedStates {
            let entry = TelemetryEntry(persistedState: state, dateProvider: dateProvider)
            telemetryMap[state.name] = entry

            if state.periodEnd <= now {
                // Period has elapsed while app was closed — fire immediately
                // (will be fired after config check in onConfigChanged)
                scheduleFireTelemetry(at: state.periodEnd, telemetryName: state.name)
            } else {
                // Re-arm timer for remaining duration
                scheduleFireTelemetry(at: state.periodEnd, telemetryName: state.name)
            }
        }
    }
}

// MARK: - Telemetry Entry

/// Represents a single telemetry pixel definition with its current state.
public final class TelemetryEntry {

    public let name: String
    public private(set) var periodStart: Date
    public private(set) var periodEnd: Date
    private let periodSeconds: Int
    private var parameters: [String: CounterParameter]
    private let dateProvider: () -> Date

    /// Initialise from remote config.
    init?(name: String, config: [String: Any], dateProvider: @escaping () -> Date) {
        self.name = name
        self.dateProvider = dateProvider

        // Parse trigger.period
        guard let trigger = config["trigger"] as? [String: Any],
              let period = trigger["period"] as? [String: Any] else { return nil }

        self.periodSeconds = Self.periodToSeconds(period)
        guard periodSeconds > 0 else { return nil }

        let now = dateProvider()
        self.periodStart = now
        self.periodEnd = now.addingTimeInterval(TimeInterval(periodSeconds))

        // Parse parameters
        var params: [String: CounterParameter] = [:]
        if let parametersConfig = config["parameters"] as? [String: [String: Any]] {
            for (paramName, paramConfig) in parametersConfig {
                guard let template = paramConfig["template"] as? String, template == "counter" else { continue }
                guard let source = paramConfig["source"] as? String else { continue }

                var buckets: [BucketConfig] = []
                if let bucketsArray = paramConfig["buckets"] as? [[String: Any]] {
                    for bucketDict in bucketsArray {
                        guard let minInclusive = bucketDict["minInclusive"] as? Int,
                              let bucketName = bucketDict["name"] as? String else { continue }
                        let maxExclusive = bucketDict["maxExclusive"] as? Int
                        buckets.append(BucketConfig(minInclusive: minInclusive, maxExclusive: maxExclusive, name: bucketName))
                    }
                }

                params[paramName] = CounterParameter(source: source, buckets: buckets)
            }
        }

        self.parameters = params
    }

    /// Restore from persisted state.
    init(persistedState: TelemetryPersistedState, dateProvider: @escaping () -> Date) {
        self.name = persistedState.name
        self.dateProvider = dateProvider
        self.periodStart = persistedState.periodStart
        self.periodEnd = persistedState.periodEnd
        self.periodSeconds = persistedState.periodSeconds

        var params: [String: CounterParameter] = [:]
        for (paramName, paramState) in persistedState.parameters {
            params[paramName] = CounterParameter(
                source: paramState.source,
                buckets: paramState.buckets,
                data: paramState.data,
                stopCounting: paramState.stopCounting
            )
        }
        self.parameters = params
    }

    /// Start collection.
    func start() {
        let now = dateProvider()
        self.periodStart = now
        self.periodEnd = now.addingTimeInterval(TimeInterval(periodSeconds))
    }

    /// Process an event. If a counter parameter's source matches, increment it.
    func handleEvent(type: String) {
        guard dateProvider() <= periodEnd else { return }

        for (_, param) in parameters {
            guard param.source == type else { continue }
            guard !param.stopCounting else { continue }

            param.data += 1

            // Check if there's any potential future bucket we could move into
            if !param.buckets.contains(where: { param.data < $0.minInclusive }) {
                param.stopCounting = true
            }
        }
    }

    /// Fire the pixel.
    func fire(pixelFiring: EventHubPixelFiring) {
        let pixelData = buildPixel()

        let additionalParameters = [
            "attributionPeriod": String(Self.calculateAttributionPeriod(startTime: periodStart,
                                                                        periodSeconds: periodSeconds))
        ]

        guard !pixelData.isEmpty else { return }

        var allParams = pixelData
        for (key, value) in additionalParameters {
            allParams[key] = value
        }

        pixelFiring.fireEventHubPixel(named: name, parameters: allParams)
    }

    func buildPixel() -> [String: String] {
        var params: [String: String] = [:]
        for (paramName, param) in parameters {
            if let bucket = Self.bucketCount(count: param.data, buckets: param.buckets) {
                params[paramName] = bucket.name
            }
        }
        return params
    }

    var persistedState: TelemetryPersistedState {
        var paramStates: [String: ParameterPersistedState] = [:]
        for (name, param) in parameters {
            paramStates[name] = ParameterPersistedState(
                template: "counter",
                data: param.data,
                source: param.source,
                buckets: param.buckets,
                stopCounting: param.stopCounting
            )
        }
        return TelemetryPersistedState(
            name: name,
            periodStart: periodStart,
            periodEnd: periodEnd,
            periodSeconds: periodSeconds,
            parameters: paramStates
        )
    }

    // MARK: - Static Helpers

    static func periodToSeconds(_ period: [String: Any]) -> Int {
        let seconds = period["seconds"] as? Int ?? 0
        let minutes = period["minutes"] as? Int ?? 0
        let hours = period["hours"] as? Int ?? 0
        let days = period["days"] as? Int ?? 0

        return seconds + minutes * 60 + hours * 3600 + days * 86400
    }

    /// Attribution period: the start of the period in which the attribution window closes,
    /// represented as a UTC Unix timestamp.
    ///
    /// Examples:
    ///   (2026-01-02T00:01:00Z, days:1)  → 2026-01-03T00:00:00Z → 1735862400
    ///   (2026-01-02T17:15:00Z, hours:1) → 2026-01-02T18:00:00Z
    ///   (2026-01-03T00:00:00Z, days:1)  → 2026-01-04T00:00:00Z
    static func calculateAttributionPeriod(startTime: Date, periodSeconds: Int) -> Int {
        let epochSecs = Int(startTime.timeIntervalSince1970)
        let snapped = (epochSecs / periodSeconds) * periodSeconds
        return snapped + periodSeconds
    }

    /// Allocate a count to the first matching bucket.
    static func bucketCount(count: Int, buckets: [BucketConfig]) -> BucketConfig? {
        for bucket in buckets {
            if count >= bucket.minInclusive {
                if let maxExclusive = bucket.maxExclusive {
                    if count < maxExclusive {
                        return bucket
                    }
                } else {
                    return bucket
                }
            }
        }
        return nil
    }
}

// MARK: - Counter Parameter

final class CounterParameter {
    let source: String
    let buckets: [BucketConfig]
    var data: Int
    var stopCounting: Bool

    init(source: String, buckets: [BucketConfig], data: Int = 0, stopCounting: Bool = false) {
        self.source = source
        self.buckets = buckets
        self.data = data
        self.stopCounting = stopCounting
    }
}
