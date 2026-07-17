//
//  LaunchTimeMetricsSubscriber.swift
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
import UIKit
import MetricKit
import Core
import Common
import Persistence

@available(iOSApplicationExtension, unavailable)
final class LaunchTimeMetricsSubscriber: NSObject, MXMetricManagerSubscriber {

    private let processor: LaunchTimeMetricsProcessor
    private let store: KeyValueStoring
    private let currentAppVersion: String
    private let dateProvider: () -> Date
    private let fire: (Pixel.Event, [String: String]) -> Void

    /// Serialises all report processing. Both entry points — MetricKit's system-delivered
    /// payloads (`didReceive`) and our own drain of retained payloads (`processPastPayloads`) —
    /// run here, off the main thread and never concurrently, so the `lastProcessedEnd`
    /// read-modify-write can't race.
    private let processingQueue = DispatchQueue(label: "com.duckduckgo.ios.launchTimeMetrics")

    /// `deviceType` is resolved on the caller's (main) thread via its default argument,
    /// then passed explicitly to `Pixel.fire` so the background queue never reads
    /// `UIDevice.current`. Tests inject their own `fire` and bypass this.
    init(processor: LaunchTimeMetricsProcessor = LaunchTimeMetricsProcessor(),
         store: KeyValueStoring,
         currentAppVersion: String = AppVersion.shared.versionNumber,
         deviceType: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         dateProvider: @escaping () -> Date = Date.init,
         fire: ((Pixel.Event, [String: String]) -> Void)? = nil) {
        self.processor = processor
        self.store = store
        self.currentAppVersion = currentAppVersion
        self.dateProvider = dateProvider
        self.fire = fire ?? { pixel, params in
            Pixel.fire(pixel: pixel, forDeviceType: deviceType, withAdditionalParameters: params)
        }
        super.init()
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: payloads.compactMap(Self.report(from:)))
        }
    }

    /// Drains MetricKit's retained past payloads. Called on launch and on every foreground.
    /// Reads `pastPayloads` and processes it on the serial queue, so nothing runs on the main
    /// thread; the dedup marker makes repeated calls safe.
    func processPastPayloads() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.process(reports: MXMetricManager.shared.pastPayloads.compactMap(Self.report(from:)))
        }
    }

    // MARK: - Report handling

    func process(reports: [LaunchMetricsReport]) {
        let dataPoints = processor.dataPointsToSendPixelsFor(from: reports,
                                                             currentAppVersion: currentAppVersion,
                                                             now: dateProvider(),
                                                             lastProcessedEnd: lastProcessedEnd)
        for point in dataPoints {
            fire(point.pixelEvent, [
                PixelParameters.launchTimeMinMs: String(Int(point.minMs.rounded())),
                PixelParameters.launchTimeMaxMs: String(Int(point.maxMs.rounded()))
            ])
        }
        if let newest = processor.newestTimestamp(in: reports) {
            lastProcessedEnd = max(newest, lastProcessedEnd ?? .distantPast)
        }
    }

    // MARK: - Persistence

    private var lastProcessedEnd: Date? {
        get { (store.object(forKey: Const.lastProcessedKey) as? Double).map(Date.init(timeIntervalSince1970:)) }
        set { store.set(newValue?.timeIntervalSince1970, forKey: Const.lastProcessedKey) }
    }

    private enum Const {
        static let lastProcessedKey = "LaunchTimeMetrics.lastProcessedEnd"
    }

    // MARK: - MetricKit adapter

    static func report(from payload: MXMetricPayload) -> LaunchMetricsReport? {
        guard let launch = payload.applicationLaunchMetrics else { return nil }
        var histograms: [LaunchType: [LaunchHistogramBucket]] = [
            .coldStart: buckets(from: launch.histogrammedTimeToFirstDraw),
            .resume: buckets(from: launch.histogrammedApplicationResumeTime)
        ]
        if #available(iOS 15.2, *) {
            histograms[.optimizedFirstDraw] = buckets(from: launch.histogrammedOptimizedTimeToFirstDraw)
        }
        return LaunchMetricsReport(appVersion: payload.latestApplicationVersion,
                                   includesMultipleAppVersions: payload.includesMultipleApplicationVersions,
                                   timeStampEnd: payload.timeStampEnd,
                                   histograms: histograms)
    }

    static func buckets(from histogram: MXHistogram<UnitDuration>) -> [LaunchHistogramBucket] {
        var result: [LaunchHistogramBucket] = []
        let enumerator = histogram.bucketEnumerator
        while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitDuration> {
            result.append(LaunchHistogramBucket(startMs: bucket.bucketStart.converted(to: .milliseconds).value,
                                                endMs: bucket.bucketEnd.converted(to: .milliseconds).value,
                                                count: bucket.bucketCount))
        }
        return result
    }
}

private extension LaunchTimeDataPoint {
    var pixelEvent: Pixel.Event {
        switch launchType {
        case .coldStart: return .launchTimeFirstDraw
        case .resume: return .launchTimeResume
        case .optimizedFirstDraw: return .launchTimeOptimizedFirstDraw
        }
    }
}
