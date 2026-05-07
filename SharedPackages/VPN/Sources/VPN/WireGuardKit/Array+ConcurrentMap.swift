// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation

private final class ConcurrentMapResults<Value: Sendable>: @unchecked Sendable {
    private var values: [Value?]
    private let lock = NSLock()

    init(count: Int) {
        self.values = [Value?](repeating: nil, count: count)
    }

    func set(_ value: Value, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        values[index] = value
    }

    func resolved() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return values.map { $0! }
    }
}

extension Array {

    /// Returns an array containing the results of mapping the given closure over the sequence’s
    /// elements concurrently.
    ///
    /// - Parameters:
    ///   - queue: The queue for performing concurrent computations.
    ///            If the given queue is serial, the values are mapped in a serial fashion.
    ///            Pass `nil` to perform computations on the current queue.
    ///   - transform: the block to perform concurrent computations over the given element.
    /// - Returns: an array of concurrently computed values.
    func concurrentMap<U: Sendable>(queue: DispatchQueue?, _ transform: @Sendable @escaping (Element) -> U) -> [U] where Element: Sendable {
        let results = ConcurrentMapResults<U>(count: self.count)

        let work: @Sendable () -> Void = {
            DispatchQueue.concurrentPerform(iterations: self.count) { index in
                let value = transform(self[index])
                results.set(value, at: index)
            }
        }

        if let queue {
            queue.sync(execute: work)
        } else {
            work()
        }

        return results.resolved()
    }
}
