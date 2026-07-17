//
//  LaunchTimeMetricsService.swift
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
import MetricKit
import Core
import Persistence
import PrivacyConfig

/// Owns the MetricKit launch-time subscriber. When enabled, registers it with
/// `MXMetricManager` and drains any already-available past payloads on start and
/// on every foreground.
@available(iOSApplicationExtension, unavailable)
final class LaunchTimeMetricsService {

    private let subscriber: LaunchTimeMetricsSubscriber?

    init(featureFlagger: FeatureFlagger,
         store: KeyValueStoring = UserDefaults.standard) {
        guard featureFlagger.isFeatureOn(.launchTimeMetrics) else {
            self.subscriber = nil
            return
        }

        let subscriber = LaunchTimeMetricsSubscriber(store: store)
        self.subscriber = subscriber
        MXMetricManager.shared.add(subscriber)
        processPastPayloads()
    }

    /// Re-processes MetricKit's retained past payloads. Called on `applicationDidBecomeActive`
    /// to pick up payloads delivered while the app was inactive.
    func resume() {
        processPastPayloads()
    }

    /// Feeds `MXMetricManager`'s retained past payloads through the subscriber. The dedup
    /// marker prevents double-sending, so this is safe to call repeatedly.
    private func processPastPayloads() {
        guard let subscriber else { return }
        subscriber.didReceive(MXMetricManager.shared.pastPayloads)
    }

    deinit {
        if let subscriber {
            MXMetricManager.shared.remove(subscriber)
        }
    }
}
