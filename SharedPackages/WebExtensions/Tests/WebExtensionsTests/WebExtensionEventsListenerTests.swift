//
//  WebExtensionEventsListenerTests.swift
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
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionEventsListenerTests: XCTestCase {

    @MainActor
    func testWhenControllerIsUnavailable_ThenCallbackIsQueued() {
        let listener = WebExtensionEventsListener()

        listener.didSelectTabs([])

        XCTAssertEqual(listener.pendingCallbacksCount, 1)
        XCTAssertEqual(listener.droppedCallbacksCount, 0)
    }

    @MainActor
    func testWhenControllerIsSet_ThenPendingCallbacksAreFlushed() {
        let listener = WebExtensionEventsListener()
        let controller = WKWebExtensionController()

        listener.didSelectTabs([])
        listener.controller = controller

        XCTAssertEqual(listener.pendingCallbacksCount, 0)
        XCTAssertEqual(listener.droppedCallbacksCount, 0)
    }
}
