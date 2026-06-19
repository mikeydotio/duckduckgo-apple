//
//  VPNStrictRoutingReminderStore.swift
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

/// Tracks the dates used to pace the "turn Strict routing back on" reminder tip:
/// when the user disabled Strict routing, and when the reminder was last shown.
public protocol VPNStrictRoutingReminderStore {

    /// Stamps the disabled date with the current date, but only if one isn't already set,
    /// so the grace period is anchored to the first time we noticed Strict routing off.
    func recordDisabledIfNecessary()

    /// Stamps the last-shown date with the current date.
    func recordReminderShown()

    /// Clears both dates. Called when Strict routing is turned back on, so the next time it's
    /// disabled the grace period and recurrence start fresh.
    func clear()

    func secondsSinceDisabled() -> TimeInterval?
    func secondsSinceReminderShown() -> TimeInterval?

    /// A debug-only override for the reminder interval, in seconds. `nil` means use the default.
    var overriddenInterval: TimeInterval? { get set }

    /// A debug-only flag that forces the pre-macOS-14 fallback reminder to show immediately,
    /// regardless of OS version or timing, so it can be exercised without an older device.
    var forceFallbackReminder: Bool { get set }
}

public struct DefaultVPNStrictRoutingReminderStore: VPNStrictRoutingReminderStore {

    private enum Constants {
        static let disabledDateKey = "com.duckduckgo.network-protection.strict-routing.disabled-date"
        static let reminderShownDateKey = "com.duckduckgo.network-protection.strict-routing.reminder-last-shown-date"
        static let overriddenIntervalKey = "com.duckduckgo.network-protection.strict-routing.debug.interval-seconds"
        static let forceFallbackReminderKey = "com.duckduckgo.network-protection.strict-routing.debug.force-fallback"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public var overriddenInterval: TimeInterval? {
        get {
            userDefaults.object(forKey: Constants.overriddenIntervalKey) as? TimeInterval
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: Constants.overriddenIntervalKey)
            } else {
                userDefaults.removeObject(forKey: Constants.overriddenIntervalKey)
            }
        }
    }

    public var forceFallbackReminder: Bool {
        get {
            userDefaults.bool(forKey: Constants.forceFallbackReminderKey)
        }
        set {
            userDefaults.set(newValue, forKey: Constants.forceFallbackReminderKey)
        }
    }

    public func recordDisabledIfNecessary() {
        guard userDefaults.double(forKey: Constants.disabledDateKey) == 0 else {
            return
        }

        userDefaults.set(Date().timeIntervalSinceReferenceDate, forKey: Constants.disabledDateKey)
    }

    public func recordReminderShown() {
        userDefaults.set(Date().timeIntervalSinceReferenceDate, forKey: Constants.reminderShownDateKey)
    }

    public func clear() {
        userDefaults.removeObject(forKey: Constants.disabledDateKey)
        userDefaults.removeObject(forKey: Constants.reminderShownDateKey)
    }

    public func secondsSinceDisabled() -> TimeInterval? {
        secondsSince(key: Constants.disabledDateKey)
    }

    public func secondsSinceReminderShown() -> TimeInterval? {
        secondsSince(key: Constants.reminderShownDateKey)
    }

    private func secondsSince(key: String) -> TimeInterval? {
        let timestamp = userDefaults.double(forKey: key)

        if timestamp == 0 {
            return nil
        }

        return Date().timeIntervalSinceReferenceDate - timestamp
    }
}
