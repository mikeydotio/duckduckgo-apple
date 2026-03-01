//
//  AutofillLoginSessionTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo
@testable import BrowserServicesKit

final class AutofillLoginSessionTests: XCTestCase {

    private var autofillSession = AutofillLoginSession(sessionTimeout: 2)

    func testWhenThereIsNoSessionCreationDateThenAutofillSessionIsFalse() {
        XCTAssertFalse(autofillSession.isSessionValid)
    }

    func testWhenSessionStartedThenAutofillSessionIsValid() {
        autofillSession.startSession()
        assertSessionBecomesValid()
        XCTAssertTrue(autofillSession.isSessionValid)
    }

    func testWhenSessionEndedThenAutofillSessionIsInvalid() {
        autofillSession.startSession()
        autofillSession.endSession()
        XCTAssertFalse(autofillSession.isSessionValid)
    }

    func testWhenSessionExpiredThenAutofillSessionIsInvalid() {
        autofillSession.startSession()
        assertSessionBecomesValid()
        assertSessionBecomesInvalid()
        XCTAssertFalse(autofillSession.isSessionValid)
    }

    func testWhenSessionIsValidAndAccountIsSetThenAccountIsReturned() {
        autofillSession.startSession()
        let account = SecureVaultModels.WebsiteAccount(title: nil, username: "username", domain: "test")
        autofillSession.lastAccessedAccount = account
        XCTAssertNotNil(autofillSession.lastAccessedAccount)
    }

    func testWhenSessionIsInvalidAndAccountIsSetThenNoAccountIsReturned() {
        autofillSession.startSession()
        let account = SecureVaultModels.WebsiteAccount(title: nil, username: "username", domain: "test")
        autofillSession.lastAccessedAccount = account
        autofillSession.endSession()
        XCTAssertNil(autofillSession.lastAccessedAccount)
    }

    private func assertSessionBecomesValid(file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { [unowned self] _, _ in
                autofillSession.isSessionValid
            },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 1)
        XCTAssertEqual(result, .completed, file: file, line: line)
    }

    private func assertSessionBecomesInvalid(file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { [unowned self] _, _ in
                !autofillSession.isSessionValid
            },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
}
