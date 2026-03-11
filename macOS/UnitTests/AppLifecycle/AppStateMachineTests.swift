//
//  AppStateMachineTests.swift
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

import AppKit
import Testing
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mocks

@MainActor
final class MockInitializing: InitializingHandling {

    var shouldThrowOnLaunching = false
    private(set) var willFinishLaunchingCalled = false

    init() {}

    func handleWillFinishLaunching() {
        willFinishLaunchingCalled = true
    }

    func makeLaunchingState() throws -> any LaunchingHandling {
        if shouldThrowOnLaunching {
            throw NSError(domain: "test", code: 1)
        }
        return MockLaunching()
    }

}

@MainActor
final class MockLaunching: LaunchingHandling {

    var shouldThrowOnForeground = false

    func makeForegroundState() throws -> any ForegroundHandling {
        if shouldThrowOnForeground {
            throw NSError(domain: "test", code: 2)
        }
        return MockForeground()
    }

}

@MainActor
final class MockForeground: ForegroundHandling {

    private(set) var eventLog: [String] = []
    var terminationReply: NSApplication.TerminateReply = .terminateNow

    var onTransitionCalled: Bool { eventLog.contains("onTransition") }
    var didReturnCalled: Bool { eventLog.contains("didReturn") }

    private(set) var lastAsyncTerminationClosure: (@MainActor () -> Void)?

    func onTransition() { eventLog.append("onTransition") }
    func didReturn() { eventLog.append("didReturn") }

    func handleTerminationRequest(onAsyncTerminationApproved: @escaping @MainActor () -> Void) -> NSApplication.TerminateReply {
        eventLog.append("handleTerminationRequest")
        lastAsyncTerminationClosure = onAsyncTerminationApproved
        return terminationReply
    }

}

@MainActor
final class MockTerminating: TerminatingHandling {

    let error: Error?
    private(set) var terminateCalled = false

    init(error: Error) {
        self.error = error
    }

    init() {
        self.error = nil
    }

    func terminate() {
        terminateCalled = true
    }

}

@MainActor
final class MockTerminatingStateFactory: TerminatingStateFactory {

    private(set) var lastCreatedTerminating: MockTerminating?

    func makeTerminatingState(error: Error) -> any TerminatingHandling {
        let mock = MockTerminating(error: error)
        lastCreatedTerminating = mock
        return mock
    }

    func makeTerminatingState() -> any TerminatingHandling {
        let mock = MockTerminating()
        lastCreatedTerminating = mock
        return mock
    }

}

// MARK: - Initializing Tests

@MainActor
@Suite("AppStateMachine initializing origin transition tests", .serialized)
final class InitializingTests {

    let stateMachine: AppStateMachine
    let terminatingFactory = MockTerminatingStateFactory()

    init() {
        stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()), terminatingStateFactory: terminatingFactory)
    }

    @Test("willFinishLaunching should stay in initializing and call handleWillFinishLaunching")
    func willFinishLaunching() {
        stateMachine.handle(.willFinishLaunching)
        #expect(stateMachine.currentState.name == "initializing")

        if case .initializing(let initializing) = stateMachine.currentState,
           let mock = initializing as? MockInitializing {
            #expect(mock.willFinishLaunchingCalled)
        } else {
            Issue.record("Expected initializing state with MockInitializing")
        }
    }

    @Test("didFinishLaunching should transition from initializing to launching")
    func transitionToLaunching() {
        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "launching")
    }

    @Test("didFinishLaunching with error should transition to terminating")
    func transitionToTerminatingOnError() {
        if case .initializing(let initializing) = stateMachine.currentState,
           let mock = initializing as? MockInitializing {
            mock.shouldThrowOnLaunching = true
        }
        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("didBecomeActive in initializing should be ignored")
    func didBecomeActiveIgnored() {
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "initializing")
    }

}

// MARK: - Launching Tests

@MainActor
@Suite("AppStateMachine launching origin transition tests", .serialized)
final class LaunchingTests {

    let stateMachine: AppStateMachine
    let terminatingFactory = MockTerminatingStateFactory()

    init() {
        stateMachine = AppStateMachine(initialState: .launching(MockLaunching()), terminatingStateFactory: terminatingFactory)
    }

    @Test("didBecomeActive should transition from launching to foreground and call onTransition")
    func transitionToForeground() {
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            #expect(mock.eventLog == ["onTransition"])
        } else {
            Issue.record("Expected foreground state with MockForeground")
        }
    }

    @Test("didBecomeActive with error should transition to terminating")
    func transitionToTerminatingOnError() {
        if case .launching(let launching) = stateMachine.currentState,
           let mock = launching as? MockLaunching {
            mock.shouldThrowOnForeground = true
        }
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("didFinishLaunching in launching should be ignored")
    func didFinishLaunchingIgnored() {
        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "launching")
    }

    @Test("willFinishLaunching in launching should be ignored")
    func willFinishLaunchingIgnored() {
        stateMachine.handle(.willFinishLaunching)
        #expect(stateMachine.currentState.name == "launching")
    }

}

// MARK: - Foreground Tests

@MainActor
@Suite("AppStateMachine foreground origin transition tests", .serialized)
final class ForegroundTests {

    let stateMachine: AppStateMachine
    let terminatingFactory = MockTerminatingStateFactory()

    init() {
        stateMachine = AppStateMachine(initialState: .foreground(MockForeground()), terminatingStateFactory: terminatingFactory)
    }

    @Test("didBecomeActive in foreground should call didReturn")
    func didBecomeActiveCallsDidReturn() {
        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            #expect(mock.eventLog == ["didReturn"])
        } else {
            Issue.record("Expected foreground state with MockForeground")
        }
    }

    @Test("handleTerminationRequest returning terminateNow should transition to terminating")
    func terminationApproved() {
        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateNow)
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("handleTerminationRequest returning terminateCancel should stay in foreground")
    func terminationCancelled() {
        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            mock.terminationReply = .terminateCancel
        }
        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateCancel)
        #expect(stateMachine.currentState.name == "foreground")
    }

    @Test("handleTerminationRequest returning terminateLater should stay in foreground")
    func terminationDeferred() {
        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            mock.terminationReply = .terminateLater
        }
        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateLater)
        #expect(stateMachine.currentState.name == "foreground")
    }

    @Test("terminateLater followed by async confirmation should transition to terminating")
    func asyncTerminationConfirmed() {
        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            mock.terminationReply = .terminateLater
        }
        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateLater)
        #expect(stateMachine.currentState.name == "foreground")

        // Simulate async decider chain completing with approval
        if case .foreground(let foreground) = stateMachine.currentState,
           let mock = foreground as? MockForeground {
            mock.lastAsyncTerminationClosure?()
        }
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("didFinishLaunching in foreground should be ignored")
    func didFinishLaunchingIgnored() {
        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "foreground")
    }

    @Test("willFinishLaunching in foreground should be ignored")
    func willFinishLaunchingIgnored() {
        stateMachine.handle(.willFinishLaunching)
        #expect(stateMachine.currentState.name == "foreground")
    }

}

// MARK: - Terminating Tests

@MainActor
@Suite("AppStateMachine terminating state tests", .serialized)
final class TerminatingTests {

    let stateMachine: AppStateMachine

    init() {
        stateMachine = AppStateMachine(initialState: .terminating(MockTerminating()))
    }

    @Test("All events in terminating should be ignored")
    func allEventsIgnored() {
        stateMachine.handle(.willFinishLaunching)
        #expect(stateMachine.currentState.name == "terminating")

        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "terminating")

        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("handleTerminationRequest in non-foreground state should return terminateCancel")
    func terminationRequestInTerminating() {
        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateCancel)
        #expect(stateMachine.currentState.name == "terminating")
    }

}

// MARK: - Full Lifecycle Tests

@MainActor
@Suite("AppStateMachine full lifecycle tests", .serialized)
final class FullLifecycleTests {

    @Test("Full lifecycle: initializing → launching → foreground → terminating")
    func fullLifecycle() {
        let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()), terminatingStateFactory: MockTerminatingStateFactory())

        stateMachine.handle(.willFinishLaunching)
        #expect(stateMachine.currentState.name == "initializing")

        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "launching")

        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "foreground")

        let reply = stateMachine.handleTerminationRequest()
        #expect(reply == .terminateNow)
        #expect(stateMachine.currentState.name == "terminating")
    }

    @Test("didBecomeActive before didFinishLaunching is ignored")
    func earlyDidBecomeActiveIgnored() {
        let stateMachine = AppStateMachine(initialState: .initializing(MockInitializing()), terminatingStateFactory: MockTerminatingStateFactory())

        stateMachine.handle(.didBecomeActive)
        #expect(stateMachine.currentState.name == "initializing")

        stateMachine.handle(.didFinishLaunching)
        #expect(stateMachine.currentState.name == "launching")
    }

}
