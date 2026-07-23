//
//  ClearInteractionStateTaskTests.swift
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
import Core
@testable import DuckDuckGo

@MainActor
class ClearInteractionStateTaskTests: XCTestCase {

    /// Unlike the shared `MockTabInteractionStateSource`, records what it was asked to exclude so
    /// tests can assert the task passed the *union* of every connected scene's tabs, not just one.
    private final class RecordingTabInteractionStateSource: TabInteractionStateSource {
        private(set) var lastExcludedTabs: [Tab]?

        func saveState(_ state: Any?, for tab: Tab) { }
        func popLastStateForTab(_ tab: Tab) -> Data? { nil }
        func removeStateForTab(_ tab: Tab) { }
        func removeAll(excluding excludedTabs: [Tab]) -> Result<Void, Error> { .success(()) }

        func urlsToRemove(excluding excludedTabs: [Tab]) -> Result<[URL], Error> {
            lastExcludedTabs = excludedTabs
            return .success([])
        }

        func removeStates(at urls: [URL], isCancelled: (() -> Bool)?) -> Result<Void, Error> { .success(()) }
    }

    private final class NoOpAutoClearService: AutoClearServiceProtocol {
        var isClearingEnabled = false
        var isTabClearingEnabled = false
        var autoClearTask: Task<Void, Never>?
        func waitForDataCleared() async { }
    }

    private func makeTab(url: String) -> Tab {
        Tab(link: Link(title: nil, url: URL(string: url)!))
    }

    /// `ClearInteractionStateTask.run(context:)` synchronously hops to the main queue internally
    /// (`DispatchQueue.main.sync`) to read tab models — safe when invoked from a background queue,
    /// as `LaunchOperation` always does in production, but an instant deadlock if called directly
    /// from the main thread/actor. Dispatch to a background queue here to match production and
    /// avoid exactly that deadlock.
    private func runSynchronously(_ task: ClearInteractionStateTask) {
        let done = expectation(description: "task finished")
        let context = LaunchTaskContext(isCancelled: { false }, finish: { done.fulfill() })
        DispatchQueue.global().async {
            task.run(context: context)
        }
        wait(for: [done], timeout: 2.0)
    }

    func testExcludesTabsFromEveryRegisteredScene_notJustOne() {
        let sceneRegistry = SceneRegistry()
        let tabManagerA = MockTabManager()
        tabManagerA.allTabsModel = TabsModel(tabs: [makeTab(url: "https://a.com")], desktop: true)
        let tabManagerB = MockTabManager()
        tabManagerB.allTabsModel = TabsModel(tabs: [makeTab(url: "https://b.com")], desktop: true)
        sceneRegistry.registerTabManager(tabManagerA, forSceneID: "scene-A")
        sceneRegistry.registerTabManager(tabManagerB, forSceneID: "scene-B")

        let interactionStateSource = RecordingTabInteractionStateSource()
        let task = ClearInteractionStateTask(autoClearService: NoOpAutoClearService(),
                                             interactionStateSource: interactionStateSource,
                                             sceneRegistry: sceneRegistry)
        runSynchronously(task)

        XCTAssertEqual(interactionStateSource.lastExcludedTabs?.count, 2,
                       "should exclude both scene A's and scene B's tabs, not just the registering scene's")
    }

    func testAutoClearTabClearingEnabled_skipsCleanupEntirely() {
        let sceneRegistry = SceneRegistry()
        let tabManager = MockTabManager()
        tabManager.allTabsModel = TabsModel(tabs: [makeTab(url: "https://a.com")], desktop: true)
        sceneRegistry.registerTabManager(tabManager, forSceneID: "scene-A")

        let interactionStateSource = RecordingTabInteractionStateSource()
        let autoClearService = NoOpAutoClearService()
        autoClearService.isTabClearingEnabled = true
        let task = ClearInteractionStateTask(autoClearService: autoClearService,
                                             interactionStateSource: interactionStateSource,
                                             sceneRegistry: sceneRegistry)
        runSynchronously(task)

        XCTAssertNil(interactionStateSource.lastExcludedTabs, "should not touch the interaction state source when tab clearing is enabled")
    }

}
