//
//  FullScreenVideoUserScriptTests.swift
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

final class FullScreenVideoUserScriptTests: XCTestCase {

    func testWhenPictureInPictureMessageReceivedThenDelegateIsUpdated() {
        let delegate = MockFullScreenVideoUserScriptDelegate()
        let sut = FullScreenVideoUserScript()
        sut.delegate = delegate

        sut.userContentController(
            WKUserContentController(),
            didReceive: MockWKScriptMessage(name: "pictureInPictureState", body: ["isActive": true])
        )

        XCTAssertEqual(delegate.capturedStates, [true])
    }

    func testWhenPictureInPictureMessageIsInvalidThenDelegateIsNotUpdated() {
        let delegate = MockFullScreenVideoUserScriptDelegate()
        let sut = FullScreenVideoUserScript()
        sut.delegate = delegate

        sut.userContentController(
            WKUserContentController(),
            didReceive: MockWKScriptMessage(name: "pictureInPictureState", body: ["unexpected": true])
        )

        XCTAssertTrue(delegate.capturedStates.isEmpty)
    }

    func testWhenMessageNameDoesNotMatchThenDelegateIsNotUpdated() {
        let delegate = MockFullScreenVideoUserScriptDelegate()
        let sut = FullScreenVideoUserScript()
        sut.delegate = delegate

        sut.userContentController(
            WKUserContentController(),
            didReceive: MockWKScriptMessage(name: "otherMessage", body: ["isActive": true])
        )

        XCTAssertTrue(delegate.capturedStates.isEmpty)
    }
}

private final class MockFullScreenVideoUserScriptDelegate: FullScreenVideoUserScriptDelegate {
    private(set) var capturedStates: [Bool] = []

    func fullScreenVideoUserScript(_ script: FullScreenVideoUserScript, didChangePictureInPictureState isActive: Bool) {
        capturedStates.append(isActive)
    }
}
