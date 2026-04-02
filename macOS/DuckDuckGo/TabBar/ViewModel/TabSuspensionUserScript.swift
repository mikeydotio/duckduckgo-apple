//
//  TabSuspensionUserScript.swift
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

import Common
import UserScript
import WebKit

@MainActor
protocol TabSuspensionUserScriptDelegate: AnyObject {
    func tabSuspensionUserScript(_ userScript: TabSuspensionUserScript, didChangeCanBeSuspended canBeSuspended: Bool)
}

/// Content Scope isolated-world subfeature that receives tab suspension
/// eligibility notifications from JS.
///
/// The JS side is implemented in `content-scope-scripts/injected/src/features/tab-suspension.js`.
/// It detects conditions that prevent tab suspension (e.g. focused input fields)
/// and sends a `canBeSuspended` notification when the state changes.
final class TabSuspensionUserScript: NSObject, Subfeature {

    struct CanBeSuspendedPayload: Codable {
        let canBeSuspended: Bool
    }

    let messageOriginPolicy: MessageOriginPolicy = .all
    let featureName: String = "tabSuspension"

    weak var broker: UserScriptMessageBroker?
    weak var delegate: TabSuspensionUserScriptDelegate?

    enum MessageNames: String, CaseIterable {
        case canBeSuspended
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .canBeSuspended:
            return { [weak self] in try await self?.handleCanBeSuspended(params: $0, original: $1) }
        default:
            return nil
        }
    }

    @MainActor
    private func handleCanBeSuspended(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let payload: CanBeSuspendedPayload = DecodableHelper.decode(from: params) else { return nil }

        delegate?.tabSuspensionUserScript(self, didChangeCanBeSuspended: payload.canBeSuspended)
        return nil
    }
}
