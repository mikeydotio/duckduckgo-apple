//
//  CardItemListTests.swift
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

import XCTest
@testable import UIComponents

final class CardItemListSelectActionTests: XCTestCase {

    func testSelectAction_withOutOfBoundsIndex_returnsNil() {
        let handler = CardItemList.selectAction(over: ["a"]) { _ in }

        XCTAssertNil(handler(5))
        XCTAssertNil(handler(-1))
    }

    func testSelectAction_withEmptyCollection_returnsNilForAnyIndex() {
        let handler = CardItemList.selectAction(over: [String]()) { _ in }

        XCTAssertNil(handler(0))
    }

    func testSelectAction_withValidSelectableRow_returnsActionThatFiresWithElement() {
        var captured: String?
        let handler = CardItemList.selectAction(over: ["a", "b", "c"]) { captured = $0 }

        let action = handler(1)

        XCTAssertNotNil(action)
        action?()
        XCTAssertEqual(captured, "b")
    }

    func testSelectAction_withSelectabilityPredicate_gatesRows() {
        let handler = CardItemList.selectAction(over: [1, 2, 3], where: { $0.isMultiple(of: 2) }) { _ in }

        XCTAssertNil(handler(0))    // element 1 — not selectable
        XCTAssertNotNil(handler(1)) // element 2 — selectable
    }

    func testSelectAction_doesNotFireActionUntilInvoked() {
        var fired = false
        let handler = CardItemList.selectAction(over: ["x"]) { _ in fired = true }

        _ = handler(0)
        XCTAssertFalse(fired)

        handler(0)?()
        XCTAssertTrue(fired)
    }
}

#endif
