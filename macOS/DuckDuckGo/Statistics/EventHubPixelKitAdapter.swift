//
//  EventHubPixelKitAdapter.swift
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

import BrowserServicesKit
import Foundation
import PixelKit

/// macOS implementation of EventHubPixelFiring using PixelKit.
struct EventHubPixelKitAdapter: EventHubPixelFiring {

    func fireEventHubPixel(named pixelName: String, parameters: [String: String]) {
        let event = EventHubPixelKitEvent(pixelName: pixelName, params: parameters)
        PixelKit.fire(event)
    }
}

/// A PixelKitEvent with a dynamic name determined by remote config.
struct EventHubPixelKitEvent: PixelKitEvent {
    let pixelName: String
    let params: [String: String]

    var name: String { pixelName }
    var parameters: [String: String]? { params }
    var error: NSError? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
