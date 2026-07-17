//
//  WakeConnectivityMonitorTests.swift
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
import XCTest
@testable import VPN

@MainActor
final class WakeConnectivityMonitorTests: XCTestCase {

    /// Fixed wake instant so handshake timestamps can be set relative to it deterministically.
    private let wakeEpoch: TimeInterval = 1_000_000

    private final class MockHandshakeReporter: HandshakeReporting {
        var mostRecentHandshake: TimeInterval = 0
        func getMostRecentHandshake() async throws -> TimeInterval { mostRecentHandshake }
    }

    private func makeMonitor(
        handshake: TimeInterval = 0,
        networkAvailable: Bool = true,
        confirmationWindow: TimeInterval = 0.1,
        onResult: @escaping (WakeConnectivityResult) -> Void
    ) -> (WakeConnectivityMonitor, MockHandshakeReporter) {
        let reporter = MockHandshakeReporter()
        reporter.mostRecentHandshake = handshake
        let monitor = WakeConnectivityMonitor(
            handshakeReporter: reporter,
            now: { Date(timeIntervalSince1970: self.wakeEpoch) },
            confirmationWindow: confirmationWindow,
            networkAvailability: { networkAvailable },
            onResult: onResult
        )
        return (monitor, reporter)
    }

    // MARK: - Positive confirmation

    func testConnectedTesterResultResolvesRestoredImmediately() {
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor { result = $0 }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.connected)

        // Resolution is synchronous on the tester result — no need to wait for the window.
        XCTAssertEqual(result, .restored)
    }

    func testReconnectedTesterResultResolvesRestored() {
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor { result = $0 }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.reconnected(failureCount: 3))

        XCTAssertEqual(result, .restored)
    }

    func testFreshHandshakeResolvesRestoredAtWindowEnd() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        // Handshake newer than the wake means traffic is flowing even without a tester verdict.
        let (monitor, _) = makeMonitor(handshake: wakeEpoch + 30) {
            result = $0
            expectation.fulfill()
        }

        monitor.noteWake()

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .restored)
    }

    // MARK: - Not-restored reasons

    func testTesterFailedToStartReportsTesterNotRunning() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: true) {
            result = $0
            expectation.fulfill()
        }

        let window = monitor.noteWake()
        monitor.noteMonitorStartFailed(forWindow: window)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .testerNotRunning))
    }

    func testTesterReportedDisconnectedReportsTesterFailed() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: true) {
            result = $0
            expectation.fulfill()
        }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.disconnected(failureCount: 1))

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .testerFailed))
    }

    func testNoNetworkReportsNetworkDown() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        // Network unavailable trumps the tester reasons — the VPN can't be blamed.
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: false) {
            result = $0
            expectation.fulfill()
        }

        let window = monitor.noteWake()
        monitor.noteMonitorStartFailed(forWindow: window)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .networkDown))
    }

    func testStaleHandshakeWithNoOtherSignalReportsHandshakeStale() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: true) {
            result = $0
            expectation.fulfill()
        }

        monitor.noteWake()

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .handshakeStale))
    }

    // MARK: - Lifecycle

    func testCancelPreventsResolution() async {
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100) { result = $0 }

        monitor.noteWake()
        monitor.cancel()

        // Wait past the window; nothing should have been emitted.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(result)
    }

    func testResultIgnoredWhenNoWindowOpen() {
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor { result = $0 }

        // No noteWake() — results outside a wake window must be ignored (normal operation fires these too).
        monitor.recordConnectionTestResult(.connected)

        XCTAssertNil(result)
    }

    func testOnlyOneResultPerWindow() async {
        var results: [WakeConnectivityResult] = []
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100) { results.append($0) }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.connected) // resolves restored
        monitor.recordConnectionTestResult(.disconnected(failureCount: 1)) // ignored — already resolved

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(results, [.restored])
    }

    // MARK: - Network availability gating

    func testConnectedWhileNetworkDownDoesNotResolveRestored() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        // A full outage after wake makes the tester report `.connected` (both probes fail), which would otherwise
        // be a false "restored". With no network, it must fall through to `networkDown` at window close instead.
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: false) {
            result = $0
            expectation.fulfill()
        }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.connected)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .networkDown))
    }

    func testConnectedResolvesRestoredAfterNetworkRecoversMidWindow() {
        var networkUp = false
        var result: WakeConnectivityResult?
        let reporter = MockHandshakeReporter()
        reporter.mostRecentHandshake = wakeEpoch - 100
        let monitor = WakeConnectivityMonitor(
            handshakeReporter: reporter,
            now: { Date(timeIntervalSince1970: self.wakeEpoch) },
            confirmationWindow: 5, // long enough that the window doesn't close during the synchronous calls
            networkAvailability: { networkUp },
            onResult: { result = $0 }
        )

        monitor.noteWake()
        // Network down: the tester's `.connected` is gated and dropped without latching any reason.
        monitor.recordConnectionTestResult(.connected)
        XCTAssertNil(result)

        // Network recovers within the window; the next `.connected` now resolves restored.
        networkUp = true
        monitor.recordConnectionTestResult(.connected)
        XCTAssertEqual(result, .restored)
    }

    // MARK: - Reason precedence

    func testTesterNotRunningWinsOverTesterFailed() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: true) {
            result = $0
            expectation.fulfill()
        }

        let window = monitor.noteWake()
        monitor.recordConnectionTestResult(.disconnected(failureCount: 1)) // sets sawDisconnected
        monitor.noteMonitorStartFailed(forWindow: window) // sets testerStartFailed — should win

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .testerNotRunning))
    }

    func testNetworkDownWinsOverTesterFailed() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: false) {
            result = $0
            expectation.fulfill()
        }

        monitor.noteWake()
        monitor.recordConnectionTestResult(.disconnected(failureCount: 1)) // sets sawDisconnected

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .networkDown))
    }

    // MARK: - Window generations

    func testStaleMonitorStartFailedIgnoredAfterNewWake() async {
        let expectation = expectation(description: "result")
        var result: WakeConnectivityResult?
        let (monitor, _) = makeMonitor(handshake: wakeEpoch - 100, networkAvailable: true) {
            result = $0
            expectation.fulfill()
        }

        let firstWindow = monitor.noteWake()
        let secondWindow = monitor.noteWake() // supersedes the first
        XCTAssertNotEqual(firstWindow, secondWindow)

        // A late failure from the first window must not taint the second — otherwise this would report
        // `testerNotRunning` instead of the second window's own `handshakeStale`.
        monitor.noteMonitorStartFailed(forWindow: firstWindow)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(result, .notRestored(reason: .handshakeStale))
    }
}
