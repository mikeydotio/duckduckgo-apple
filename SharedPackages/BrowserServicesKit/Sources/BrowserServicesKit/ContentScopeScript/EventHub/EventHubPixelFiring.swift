//
//  EventHubPixelFiring.swift
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

/// Protocol for firing eventHub telemetry pixels.
///
/// Implemented by each platform (iOS/macOS) to bridge to the platform-specific pixel infrastructure.
/// Pixel names are dynamic (determined by remote configuration) so string-based firing is used.
public protocol EventHubPixelFiring {
    func fireEventHubPixel(named pixelName: String, parameters: [String: String])
}
