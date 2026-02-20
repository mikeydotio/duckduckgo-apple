//
//  EventHubSubfeature.swift
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

import Foundation
import UserScript
import WebKit

/// Subfeature that receives `webEvent` notifications from C-S-S's webTelemetry feature
/// and forwards them to the EventHub for telemetry processing.
///
/// The webDetection feature in C-S-S routes detection events through webTelemetry's
/// `fireEvent` method, which sends `webEvent` notifications to the native client.
/// This subfeature handles those notifications and delegates to EventHub for
/// counter management, timer scheduling, and pixel firing.
///
/// ## Registration
///
/// Register on the non-isolated `ContentScopeUserScript` and add `"webTelemetry"` to
/// `allowedNonisolatedFeatures`:
///
/// ```swift
/// let eventHub = EventHub(...)
/// let subfeature = EventHubSubfeature(eventHub: eventHub)
/// contentScopeUserScript.registerSubfeature(delegate: subfeature)
/// ```
public final class EventHubSubfeature: NSObject, Subfeature {

    /// Must match the C-S-S feature name that sends `webEvent` notifications.
    public static let featureNameValue = "webTelemetry"

    public let featureName: String = EventHubSubfeature.featureNameValue

    /// webEvent messages can come from any website.
    public let messageOriginPolicy: MessageOriginPolicy = .all

    public weak var broker: UserScriptMessageBroker?

    private let eventHub: EventHub

    public init(eventHub: EventHub) {
        self.eventHub = eventHub
        super.init()
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "webEvent":
            return { [weak self] params, original in
                try await self?.handleWebEvent(params: params, original: original)
                return nil
            }
        default:
            return nil
        }
    }

    @MainActor
    private func handleWebEvent(params: Any, original: WKScriptMessage) {
        guard let dict = params as? [String: Any],
              let type = dict["type"] as? String else { return }

        let webViewID: ObjectIdentifier
        if let webView = original.webView {
            webViewID = ObjectIdentifier(webView)
        } else {
            return
        }

        eventHub.handleWebEvent(type: type, webViewIdentifier: webViewID)
    }
}
