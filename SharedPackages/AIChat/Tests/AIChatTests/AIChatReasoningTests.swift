//
//  AIChatReasoningTests.swift
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

import AIChat
import XCTest

final class AIChatReasoningTests: XCTestCase {

    func testWhenModelSupportsTwoReasoningEfforts_ThenTwoModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning])
    }

    func testWhenModelSupportsThreeReasoningEfforts_ThenThreeModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
    }

    func testWhenModelSupportsFourReasoningEfforts_ThenThreeModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium, .high])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
        XCTAssertEqual(model.reasoningEffort(for: .fast), .none)
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .low)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .high)
    }

    func testWhenModelSupportsMinimalAndMedium_ThenModesMapByMeaning() {
        let model = makeModel(supportedReasoningEffort: [.minimal, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning])
        XCTAssertEqual(model.reasoningEffort(for: .fast), .minimal)
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .medium)
    }

    func testWhenPreferredModeExceedsSupportedModes_ThenResolvedModeClampsToHighestAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low])

        XCTAssertEqual(model.resolvedReasoningMode(from: .extendedReasoning), .reasoning)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .low)
    }

    func testWhenNoPreferredMode_ThenFastReasoningModeIsUsed() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium])

        XCTAssertEqual(model.resolvedReasoningMode(from: nil), .fast)
        XCTAssertEqual(model.reasoningEffort(for: nil), AIChatReasoningEffort.none)
    }

    func testWhenModelDoesNotSupportReasoning_ThenNoReasoningModeIsAvailable() {
        let model = makeModel(supportedReasoningEffort: [])

        XCTAssertFalse(model.supportsReasoningPicker)
        XCTAssertNil(model.resolvedReasoningMode(from: .reasoning))
        XCTAssertNil(model.reasoningEffort(for: .reasoning))
    }
}

private extension AIChatReasoningTests {
    func makeModel(supportedReasoningEffort: [AIChatReasoningEffort]) -> AIChatModel {
        AIChatModel(
            id: "gpt-5.2",
            name: "GPT-5.2",
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort
        )
    }
}
