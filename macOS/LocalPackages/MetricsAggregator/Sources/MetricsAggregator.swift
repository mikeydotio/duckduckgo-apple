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

/// Errors thrown by MetricsAggregator (Rust backend).
public enum MetricsAggregatorError: Error {
    case openFailed(message: String?)
    case operationFailed(message: String?)
}

/// SQLite-backed aggregator for counter and gauge metrics, with optional bucketing
/// and outbox-based collection for pixel emission.
/// Implementation is delegated to the Rust MetricsAggregatorRust library.
public final class MetricsAggregator {

    private var handle: UnsafeMutableRawPointer?

    /// Initializes the aggregator, creating the database and schema if needed.
    /// - Parameter databaseURL: File URL for the SQLite database.
    ///   When nil, uses a standard app-support location under "MetricsAggregator".
    ///   For in-memory databases (e.g. tests), pass `URL(fileURLWithPath: ":memory:")`.
    public init(databaseURL: URL? = nil) throws {
        let url: URL
        if let databaseURL = databaseURL {
            url = databaseURL
        } else {
            let directory = FileManager.default.applicationSupportDirectoryForComponent(named: "MetricsAggregator")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("metrics_aggregator.db")
        }
        let path = url.path
        let handlePtr: UnsafeMutableRawPointer? = path.withCString { pathCStr in
            let len = path.utf8.count
            return ddg_ma_open(pathCStr, len)
        }
        guard let h = handlePtr else {
            throw MetricsAggregatorError.openFailed(message: "Failed to open database")
        }
        handle = h
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

    private func withHandle<T>(_ body: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        guard let h = handle else { throw MetricsAggregatorError.operationFailed(message: "handle closed") }
        return try body(h)
    }

    private func check(_ result: Int32) throws {
        if result == -1 {
            let msg = Self.lastErrorMessage(from: handle)
            throw MetricsAggregatorError.operationFailed(message: msg)
        }
    }

    private func withCStrings(
        pixel: String,
        name: String,
        buckets: [BucketRange]?,
        _ body: (UnsafePointer<CChar>, Int, UnsafePointer<CChar>, Int, UnsafePointer<CChar>?, Int) -> Int32
    ) throws {
        try pixel.withCString { pixelPtr in
            try name.withCString { namePtr in
                let pixelLen = pixel.utf8.count
                let nameLen = name.utf8.count
                if let buckets = buckets, !buckets.isEmpty {
                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    let data = try encoder.encode(buckets)
                    let json = String(data: data, encoding: .utf8) ?? "[]"
                    try json.withCString { jsonPtr in
                        let code = body(pixelPtr, pixelLen, namePtr, nameLen, jsonPtr, json.utf8.count)
                        try check(code)
                    }
                } else {
                    let code = body(pixelPtr, pixelLen, namePtr, nameLen, nil, 0)
                    try check(code)
                }
            }
        }
    }
}

// MARK: - Registration
public extension MetricsAggregator {
    func registerPixel(_ pixel: String, aggregationInterval: TimeInterval = 3600) throws {
        try withHandle { h in
            try pixel.withCString { ptr in
                try check(ddg_ma_register_pixel(h, ptr, pixel.utf8.count, aggregationInterval))
            }
        }
    }

    func registerCounter(pixel: String, name: String, buckets: [BucketRange]? = nil) throws {
        try withHandle { h in
            try withCStrings(pixel: pixel, name: name, buckets: buckets) { pixelPtr, pixelLen, namePtr, nameLen, bucketsPtr, bucketsLen in
                ddg_ma_register_counter(h, pixelPtr, pixelLen, namePtr, nameLen, bucketsPtr, bucketsLen)
            }
        }
    }

    func registerGauge(pixel: String, name: String, buckets: [BucketRange]? = nil) throws {
        try withHandle { h in
            try withCStrings(pixel: pixel, name: name, buckets: buckets) { pixelPtr, pixelLen, namePtr, nameLen, bucketsPtr, bucketsLen in
                ddg_ma_register_gauge(h, pixelPtr, pixelLen, namePtr, nameLen, bucketsPtr, bucketsLen)
            }
        }
    }
}

// MARK: - Mutation
public extension MetricsAggregator {
    func increment(pixel: String, name: String, by amount: Double = 1) throws {
        try withHandle { h in
            try pixel.withCString { pixelPtr in
                try name.withCString { namePtr in
                    try check(ddg_ma_increment(h, pixelPtr, pixel.utf8.count, namePtr, name.utf8.count, amount))
                }
            }
        }
    }

    func set(pixel: String, name: String, value: Double) throws {
        try withHandle { h in
            try pixel.withCString { pixelPtr in
                try name.withCString { namePtr in
                    try check(ddg_ma_set(h, pixelPtr, pixel.utf8.count, namePtr, name.utf8.count, value))
                }
            }
        }
    }
}

// MARK: - Collection
public extension MetricsAggregator {
    @discardableResult
    func collectMetrics() throws -> Int {
        try withHandle { h in
            let n = ddg_ma_collect_metrics(h)
            if n == -1 {
                let msg = Self.lastErrorMessage(from: handle)
                throw MetricsAggregatorError.operationFailed(message: msg)
            }
            return Int(n)
        }
    }
}

// MARK: - Outbox
public extension MetricsAggregator {
    func pendingPixels(limit: Int = 50) throws -> [CollectedPixel] {
        try withHandle { h in
            guard let ptr = ddg_ma_pending_pixels(h, Int32(limit)) else {
                let msg = Self.lastErrorMessage(from: handle)
                throw MetricsAggregatorError.operationFailed(message: msg)
            }
            defer { ddg_ma_free_string(ptr) }
            let json = String(cString: ptr)
            let data = Data(json.utf8)
            let decoder = JSONDecoder()
            let entries = try decoder.decode([PendingPixelEntry].self, from: data)
            return entries.compactMap { e in
                guard let start = pendingPixelDateFormatter.date(from: e.interval_start),
                      let end = pendingPixelDateFormatter.date(from: e.interval_end) else { return nil }
                return CollectedPixel(id: e.id, start: start, end: end, pixel: e.pixel, parameters: e.parameters)
            }
        }
    }

    func markSent(id: Int64) throws {
        try withHandle { try check(ddg_ma_mark_sent($0, id)) }
    }

    func markFailed(id: Int64) throws {
        try withHandle { try check(ddg_ma_mark_failed($0, id)) }
    }

    @discardableResult
    func purgeExpired(maxAttempts: Int = 5) throws -> Int {
        try withHandle { h in
            let n = ddg_ma_purge_expired(h, Int32(maxAttempts))
            if n == -1 {
                let msg = Self.lastErrorMessage(from: handle)
                throw MetricsAggregatorError.operationFailed(message: msg)
            }
            return Int(n)
        }
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
    func peek(pixel: String, name: String) throws -> Double? {
        try withHandle { h in
            var value: Double = 0
            let result: Int32 = try pixel.withCString { pixelPtr in
                try name.withCString { namePtr in
                    ddg_ma_peek(h, pixelPtr, pixel.utf8.count, namePtr, name.utf8.count, &value)
                }
            }
            if result == -1 {
                let msg = Self.lastErrorMessage(from: handle)
                throw MetricsAggregatorError.operationFailed(message: msg)
            }
            return result == 1 ? value : nil
        }
    }

    func reset() throws {
        try withHandle { try check(ddg_ma_reset($0)) }
    }
}
