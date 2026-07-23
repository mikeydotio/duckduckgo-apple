//
//  SceneRegistryTests.swift
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

import Testing
@testable import DuckDuckGo

@MainActor
@Suite("SceneRegistry active-scene aggregation tests")
final class SceneRegistryTests {

    let registry = SceneRegistry()

    @Test("Starts with zero active scenes")
    func startsEmpty() {
        #expect(registry.activeSceneCount == 0)
    }

    @Test("A single scene becoming active is reported as first-active")
    func singleSceneBecomesActive() {
        let wasFirstActive = registry.sceneDidBecomeActive()
        #expect(wasFirstActive == true)
        #expect(registry.activeSceneCount == 1)
    }

    @Test("A single scene backgrounding is reported as last-background")
    func singleSceneEntersBackground() {
        registry.sceneDidBecomeActive()
        let wasLastBackground = registry.sceneDidEnterBackground()
        #expect(wasLastBackground == true)
        #expect(registry.activeSceneCount == 0)
    }

    @Test("A single scene cycling foreground/background repeatedly is first-active/last-background every time")
    func singleSceneCyclesRepeatedly() {
        for _ in 0..<3 {
            #expect(registry.sceneDidBecomeActive() == true)
            #expect(registry.sceneDidEnterBackground() == true)
        }
        #expect(registry.activeSceneCount == 0)
    }

    @Test("Second scene becoming active is NOT reported as first-active")
    func secondSceneBecomesActiveIsNotFirst() {
        #expect(registry.sceneDidBecomeActive() == true)
        #expect(registry.sceneDidBecomeActive() == false)
        #expect(registry.activeSceneCount == 2)
    }

    @Test("Backgrounding one of two active scenes is NOT reported as last-background")
    func backgroundingOneOfTwoIsNotLast() {
        registry.sceneDidBecomeActive()
        registry.sceneDidBecomeActive()
        #expect(registry.sceneDidEnterBackground() == false)
        #expect(registry.activeSceneCount == 1)
        #expect(registry.sceneDidEnterBackground() == true)
        #expect(registry.activeSceneCount == 0)
    }

    @Test("Interleaved activation and backgrounding across three scenes only fires at the true edges")
    func interleavedThreeScenes() {
        #expect(registry.sceneDidBecomeActive() == true)   // scene A: 0 -> 1 (first)
        #expect(registry.sceneDidBecomeActive() == false)  // scene B: 1 -> 2
        #expect(registry.sceneDidBecomeActive() == false)  // scene C: 2 -> 3
        #expect(registry.sceneDidEnterBackground() == false) // scene B backgrounds: 3 -> 2
        #expect(registry.sceneDidEnterBackground() == false) // scene A backgrounds: 2 -> 1
        #expect(registry.sceneDidEnterBackground() == true)  // scene C backgrounds: 1 -> 0 (last)
        #expect(registry.activeSceneCount == 0)
    }

    @Test("The first scene ID seen is recorded as primary")
    func firstSceneIsPrimary() {
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
    }

    @Test("A second, different scene ID is not primary")
    func secondSceneIsNotPrimary() {
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
        #expect(registry.isPrimaryScene(sessionID: "scene-B") == false)
    }

    @Test("The primary scene reconnecting with the same ID stays primary")
    func primarySceneReconnectStaysPrimary() {
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
    }

    @Test("A secondary scene never becomes primary even if queried repeatedly")
    func secondarySceneNeverBecomesPrimary() {
        #expect(registry.isPrimaryScene(sessionID: "scene-A") == true)
        #expect(registry.isPrimaryScene(sessionID: "scene-B") == false)
        #expect(registry.isPrimaryScene(sessionID: "scene-B") == false)
    }

}
