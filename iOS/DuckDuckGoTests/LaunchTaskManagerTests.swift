//
//  LaunchTaskManagerTests.swift
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

import XCTest
@testable import DuckDuckGo

class LaunchTaskManagerTests: XCTestCase {

    private struct RecordingTask: LaunchTask {
        let name: String
        let onRun: () -> Void

        func run(context: LaunchTaskContext) {
            onRun()
            context.finish()
        }
    }

    func testTasksRegisteredBeforeStart_allRun() {
        let manager = LaunchTaskManager()
        let firstRan = expectation(description: "first task ran")
        let secondRan = expectation(description: "second task ran")

        manager.register(task: RecordingTask(name: "first") { firstRan.fulfill() })
        manager.register(task: RecordingTask(name: "second") { secondRan.fulfill() })
        manager.start()

        wait(for: [firstRan, secondRan], timeout: 2.0)
    }

    /// A second iPad window's `Connected.init` registers its own tasks (e.g. its
    /// `ClearInteractionStateTask`) onto this same app-global manager *after* the first window has
    /// already foregrounded and called `start()`. Before the multi-window work, registering after
    /// `start()` asserted and silently dropped the task in release builds — this must now run it.
    func testTaskRegisteredAfterStart_stillRuns() {
        let manager = LaunchTaskManager()
        let beforeStartRan = expectation(description: "task registered before start ran")
        manager.register(task: RecordingTask(name: "before-start") { beforeStartRan.fulfill() })
        manager.start()
        wait(for: [beforeStartRan], timeout: 2.0)

        let afterStartRan = expectation(description: "task registered after start still ran")
        manager.register(task: RecordingTask(name: "after-start") { afterStartRan.fulfill() })

        wait(for: [afterStartRan], timeout: 2.0)
    }

    func testStart_calledTwice_doesNotRerunAlreadyStartedTasks() {
        let manager = LaunchTaskManager()
        var runCount = 0
        let ran = expectation(description: "task ran exactly once")
        manager.register(task: RecordingTask(name: "once") {
            runCount += 1
            ran.fulfill()
        })

        manager.start()
        manager.start() // second call must be a no-op

        wait(for: [ran], timeout: 2.0)
        // Give any accidental second run a moment to (not) happen.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(runCount, 1)
    }

}
