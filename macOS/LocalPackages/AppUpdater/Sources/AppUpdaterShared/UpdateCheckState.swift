//
//  UpdateCheckState.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Actor responsible for managing update check state and rate limiting.
///
/// Handles rate limiting and in-flight tracking to prevent concurrent update checks.
/// Each UpdateController instance has its own UpdateCheckState for isolated state management.
///
public actor UpdateCheckState {

    /// Default minimum interval between update checks
    public static let defaultMinimumCheckInterval: TimeInterval = .minutes(5)

    private var lastUpdateCheckTime: Date?
    private var isCheckInProgress = false

    public init() {}

    /// Atomically checks whether a new update check can be started and, if so, marks one as in progress.
    ///
    /// Because this method has no `await` inside its body, the entire check-and-set runs as a single
    /// actor turn with no suspension points. This prevents the TOCTOU race that would arise from
    /// separate `canStartNewCheck` + `beginCheck` calls.
    ///
    /// - Parameters:
    ///   - updater: The updater instance to check for availability. Pass `nil` to skip this check.
    ///   - minimumInterval: Minimum time that must have elapsed since the last `endCheck()` call.
    ///     Pass `0` to bypass rate limiting (e.g. for user-initiated checks).
    ///     Defaults to `UpdateCheckState.defaultMinimumCheckInterval`.
    /// - Returns: `true` if the check was allowed and the in-flight flag has been set;
    ///   `false` if a check is already in flight, the updater disallows checks,
    ///   or the minimum interval has not elapsed.
    ///
    public func beginCheckIfAllowed(
        updater: UpdaterAvailabilityChecking?,
        minimumInterval: TimeInterval = UpdateCheckState.defaultMinimumCheckInterval
    ) -> Bool {
        guard !isCheckInProgress else { return false }

        if let updater = updater, !updater.canCheckForUpdates {
            return false
        }

        if let lastCheck = lastUpdateCheckTime,
           Date().timeIntervalSince(lastCheck) < minimumInterval {
            return false
        }

        isCheckInProgress = true
        return true
    }

    /// Marks the check as finished and records the current time for rate limiting.
    /// Call this in both the success and error paths of the check.
    public func endCheck() {
        isCheckInProgress = false
        lastUpdateCheckTime = Date()
    }
}
