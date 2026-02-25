//
//  MetricsAggregator.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this code except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//

import Foundation
import Common
import MetricsAggregatorRust

/// Error code returned by MetricsAggregator entrypoints (no throwing).
public enum MetricsAggregatorErrorCode {
    case success
    case openFailed(message: String?)
    case operationFailed(message: String?)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// SQLite-backed aggregator for counter and gauge metrics, with optional bucketing
/// and outbox-based collection for pixel emission.
/// Implementation is delegated to the Rust MetricsAggregatorRust library.
/// All entrypoints return an error code instead of throwing.
public final class MetricsAggregator {

    private var handle: UnsafeMutableRawPointer?

    /// Initializes the aggregator, creating the database and schema if needed.
    /// - Parameters:
    ///   - databaseURL: File URL for the SQLite database. When nil, uses a standard app-support location under "MetricsAggregator".
    ///     For in-memory databases (e.g. tests), pass `URL(fileURLWithPath: ":memory:")`.
    ///   - error: Set to the error code on failure; `.success` on success.
    /// - Returns: An instance or nil on failure (check `error`).
    public init?(databaseURL: URL? = nil, error: inout MetricsAggregatorErrorCode) {
        let url: URL
        if let databaseURL = databaseURL {
            url = databaseURL
        } else {
            let directory: URL
            do {
                directory = FileManager.default.applicationSupportDirectoryForComponent(named: "MetricsAggregator")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch let err {
                error = .openFailed(message: err.localizedDescription)
                return nil
            }
            url = directory.appendingPathComponent("metrics_aggregator.db")
        }
        let path = url.path
        let handlePtr: UnsafeMutableRawPointer? = path.withCString { pathCStr in
            ddg_ma_open(pathCStr, path.utf8.count)
        }
        guard let h = handlePtr else {
            error = .openFailed(message: "Failed to open database")
            return nil
        }
        handle = h
        error = .success
    }

    deinit {
        if let h = handle {
            ddg_ma_close(h)
            handle = nil
        }
    }

    private static func lastErrorMessage(from h: UnsafeMutableRawPointer??) -> String? {
        guard let handle = h ?? nil else { return nil }
        guard let ptr = ddg_ma_last_error_message(handle) else { return nil }
        defer { ddg_ma_free_string(ptr) }
        return String(cString: ptr)
    }

    private func applyCheck(_ result: Int32) -> MetricsAggregatorErrorCode {
        if result == -1 {
            return .operationFailed(message: Self.lastErrorMessage(from: handle))
        }
        return .success
    }
}

// MARK: - Registration
public extension MetricsAggregator {
    /// Registers an aggregation with the given name, interval, and full metric specs (counters/gauges with optional buckets).
    /// Creation date is stored for pruning relative to the latest aggregation.
    func registerAggregation(name: String, aggregationInterval: TimeInterval, metricsSpecs: [MetricSpec]) -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        let createdAt = MetricsAggregator.iso8601Now()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let specsData: Data
        do {
            specsData = try encoder.encode(metricsSpecs)
        } catch {
            return .operationFailed(message: error.localizedDescription)
        }
        let specsJson = String(data: specsData, encoding: .utf8) ?? "[]"
        return name.withCString { namePtr in
            createdAt.withCString { createdPtr in
                specsJson.withCString { specsPtr in
                    applyCheck(ddg_ma_register_aggregation(
                        h,
                        namePtr, name.utf8.count,
                        aggregationInterval,
                        createdPtr, createdAt.utf8.count,
                        specsPtr, specsJson.utf8.count
                    ))
                }
            }
        }
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

// MARK: - Mutation
public extension MetricsAggregator {
    func increment(aggregationName: String, metricName: String, by amount: Double = 1) -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        return aggregationName.withCString { pixelPtr in
            metricName.withCString { namePtr in
                applyCheck(ddg_ma_increment(h, pixelPtr, aggregationName.utf8.count, namePtr, metricName.utf8.count, amount))
            }
        }
    }

    func set(aggregationName: String, metricName: String, value: Double) -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        return aggregationName.withCString { pixelPtr in
            metricName.withCString { namePtr in
                applyCheck(ddg_ma_set(h, pixelPtr, aggregationName.utf8.count, namePtr, metricName.utf8.count, value))
            }
        }
    }
}

// MARK: - Collection
public extension MetricsAggregator {
    /// Returns (collected count, error code). On failure count is 0.
    func collectMetrics() -> (count: Int, errorCode: MetricsAggregatorErrorCode) {
        guard let h = handle else { return (0, .operationFailed(message: "handle closed")) }
        let n = ddg_ma_collect_metrics(h)
        if n == -1 {
            return (0, .operationFailed(message: Self.lastErrorMessage(from: handle)))
        }
        return (Int(n), .success)
    }
}

// MARK: - Outbox
public extension MetricsAggregator {
    /// Returns (pixels, error code). On failure pixels is empty.
    func pendingPixels(limit: Int = 50) -> (pixels: [CollectedPixel], errorCode: MetricsAggregatorErrorCode) {
        guard let h = handle else { return ([], .operationFailed(message: "handle closed")) }
        guard let ptr = ddg_ma_pending_pixels(h, Int32(limit)) else {
            return ([], .operationFailed(message: Self.lastErrorMessage(from: handle)))
        }
        defer { ddg_ma_free_string(ptr) }
        let json = String(cString: ptr)
        let data = Data(json.utf8)
        let entries: [PendingPixelEntry]
        do {
            entries = try JSONDecoder().decode([PendingPixelEntry].self, from: data)
        } catch {
            return ([], .operationFailed(message: error.localizedDescription))
        }
        let pixels = entries.compactMap { e -> CollectedPixel? in
            guard let start = pendingPixelDateFormatter.date(from: e.interval_start),
                  let end = pendingPixelDateFormatter.date(from: e.interval_end) else { return nil }
            return CollectedPixel(id: e.id, start: start, end: end, pixel: e.pixel, parameters: e.parameters)
        }
        return (pixels, .success)
    }

    func markSent(id: Int64) -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        return applyCheck(ddg_ma_mark_sent(h, id))
    }

    func markFailed(id: Int64) -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        return applyCheck(ddg_ma_mark_failed(h, id))
    }

    /// Returns (deleted count, error code). On failure count is 0.
    func purgeExpired(maxAttempts: Int = 5) -> (count: Int, errorCode: MetricsAggregatorErrorCode) {
        guard let h = handle else { return (0, .operationFailed(message: "handle closed")) }
        let n = ddg_ma_purge_expired(h, Int32(maxAttempts))
        if n == -1 {
            return (0, .operationFailed(message: Self.lastErrorMessage(from: handle)))
        }
        return (Int(n), .success)
    }

    /// Prunes aggregations whose created_at is older than (latest created_at - olderThanInterval).
    /// Use to remove old specs after a device restores an old session.
    /// Returns (deleted count, error code). On failure count is 0.
    func pruneAggregations(olderThanInterval: TimeInterval) -> (count: Int, errorCode: MetricsAggregatorErrorCode) {
        guard let h = handle else { return (0, .operationFailed(message: "handle closed")) }
        let n = ddg_ma_prune_aggregations(h, olderThanInterval)
        if n == -1 {
            return (0, .operationFailed(message: Self.lastErrorMessage(from: handle)))
        }
        return (Int(n), .success)
    }
}

private struct PendingPixelEntry: Decodable {
    let id: Int64
    let interval_start: String
    let interval_end: String
    let pixel: String
    let parameters: String
}

private let pendingPixelDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

// MARK: - Housekeeping
public extension MetricsAggregator {
    /// Returns (value or nil if no row, error code).
    func peek(aggregationName: String, metricName: String) -> (value: Double?, errorCode: MetricsAggregatorErrorCode) {
        guard let h = handle else { return (nil, .operationFailed(message: "handle closed")) }
        var value: Double = 0
        let result: Int32 = aggregationName.withCString { pixelPtr in
            metricName.withCString { namePtr in
                ddg_ma_peek(h, pixelPtr, aggregationName.utf8.count, namePtr, metricName.utf8.count, &value)
            }
        }
        if result == -1 {
            return (nil, .operationFailed(message: Self.lastErrorMessage(from: handle)))
        }
        return (result == 1 ? value : nil, .success)
    }

    func reset() -> MetricsAggregatorErrorCode {
        guard let h = handle else { return .operationFailed(message: "handle closed") }
        return applyCheck(ddg_ma_reset(h))
    }
}
