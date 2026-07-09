//
//  CardVisualPlaybackTests.swift
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

#if os(iOS)

import Testing
@testable import UIComponents

struct CardVisualPlaybackTests {

    @Test("Before the visual has appeared, playback is idle regardless of Reduce Motion")
    func whenNotAppeared_ThenPlaybackIsIdle() {
        #expect(CardVisualPlayback.resolve(hasAppeared: false, reduceMotion: false) == .idle)
        #expect(CardVisualPlayback.resolve(hasAppeared: false, reduceMotion: true) == .idle)
    }

    @Test("After appearing with motion enabled, the animation plays once")
    func whenAppearedAndMotionEnabled_ThenPlaysOnce() {
        #expect(CardVisualPlayback.resolve(hasAppeared: true, reduceMotion: false) == .playOnce)
    }

    @Test("After appearing with Reduce Motion, the animation freezes on the final frame")
    func whenAppearedAndReduceMotion_ThenFrozenAtEnd() {
        #expect(CardVisualPlayback.resolve(hasAppeared: true, reduceMotion: true) == .frozenAtEnd)
    }

}

#endif
