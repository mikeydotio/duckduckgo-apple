//
//  SubscriptionRequestCoalescerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionRequestCoalescerTests: XCTestCase {

    // MARK: - Sequential behaviour

    func testCoalesce_ReturnValueFromWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription

        let result = try await coalescer.coalesce(forceRefresh: false) { subscription }

        XCTAssertEqual(result, subscription)
    }

    func testCoalesce_ReturnsNilWhenWorkReturnsNil() async throws {
        let coalescer = SubscriptionRequestCoalescer()

        let result = try await coalescer.coalesce(forceRefresh: false) { nil }

        XCTAssertNil(result)
    }

    func testCoalesce_PropagatesErrorFromWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        struct Sentinel: Error {}

        do {
            _ = try await coalescer.coalesce(forceRefresh: false) { throw Sentinel() }
            XCTFail("Expected Sentinel to be thrown")
        } catch is Sentinel {
            // expected
        }
    }

    func testCoalesce_SequentialCallsEachRunTheirOwnWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let counter = Counter()

        _ = try await coalescer.coalesce(forceRefresh: false) { await counter.increment(); return nil }
        _ = try await coalescer.coalesce(forceRefresh: false) { await counter.increment(); return nil }

        let count = await counter.value
        XCTAssertEqual(count, 2, "Sequential calls must each invoke work independently")
    }

    /// Verifies that after a call completes, its Task is removed from inFlightTasks (the `defer`
    /// cleanup) so the next call runs fresh work and does not return the previous task's cached result.
    func testCoalesce_CompletedTaskIsNotReusedBySubsequentCall() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let first = SubscriptionMockFactory.appleSubscription
        let second = SubscriptionMockFactory.expiredSubscription

        _ = try await coalescer.coalesce(forceRefresh: false) { first }
        let result = try await coalescer.coalesce(forceRefresh: false) { second }

        XCTAssertEqual(result, second, "Post-completion call must run fresh work and not return the previous task's cached result")
    }

    func testCoalesce_DifferentKeysBothExecuteTheirWork() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let counter = Counter()

        async let r1 = coalescer.coalesce(forceRefresh: false) { await counter.increment(); return nil }
        async let r2 = coalescer.coalesce(forceRefresh: true) { await counter.increment(); return nil }
        _ = try await (r1, r2)

        let count = await counter.value
        XCTAssertEqual(count, 2, "Calls with different forceRefresh values must each invoke their own work")
    }

    // MARK: - Concurrent coalescing

    func testCoalesce_ConcurrentCallsSameKeyShareOneExecution() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        let subscription = SubscriptionMockFactory.appleSubscription
        let counter = Counter()

        // A semaphore keeps the first call's work blocked until both callers are in flight.
        let gate = AsyncSemaphore()

        async let first = coalescer.coalesce(forceRefresh: false) {
            await counter.increment()
            await gate.wait()    // hold until the second caller has joined
            return subscription
        }

        async let second = coalescer.coalesce(forceRefresh: false) {
            await counter.increment()  // must NOT be reached — second caller should join the first task
            return nil
        }

        // Let the work complete.
        gate.signal()
        let (r1, r2) = try await (first, second)

        let count = await counter.value
        XCTAssertEqual(count, 1, "Only one work closure should run for concurrent same-key calls")
        XCTAssertEqual(r1, subscription)
        XCTAssertEqual(r2, subscription, "Both callers must receive the same result")
    }

    func testCoalesce_ConcurrentCallsSameKeyBothReceiveError() async throws {
        let coalescer = SubscriptionRequestCoalescer()
        struct Sentinel: Error, Equatable {}
        let gate = AsyncSemaphore()

        async let first: DuckDuckGoSubscription? = coalescer.coalesce(forceRefresh: true) {
            await gate.wait()
            throw Sentinel()
        }
        async let second: DuckDuckGoSubscription? = coalescer.coalesce(forceRefresh: true) {
            XCTFail("Second caller's work must not execute")
            return nil
        }

        gate.signal()

        do {
            _ = try await first
            XCTFail("first should throw")
        } catch is Sentinel {}

        do {
            _ = try await second
            XCTFail("second should throw")
        } catch is Sentinel {}
    }
}

// MARK: - Test Utilities

/// Actor-isolated counter — safe to capture in `@Sendable` closures without data races.
private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Minimal async semaphore used to synchronise two concurrent tasks in tests.
private final class AsyncSemaphore: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var signalled = false
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if signalled {
                signalled = false
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            lock.unlock()
            cont.resume()
        } else {
            signalled = true
            lock.unlock()
        }
    }
}
