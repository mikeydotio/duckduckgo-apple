//
//  InterfaceOrientationPolicy.swift
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

import UIKit

/// Decides which interface orientations `MainViewController` should report as supported.
///
/// iPad always reports every orientation (`.all`), including upside-down: iPadOS only offers
/// classic Split View / Slide Over (e.g. dragging an app from the Dock onto another) to apps
/// that declare full orientation support, and this app's static Info.plist declaration was
/// already being undermined by a narrower runtime mask. iPhone keeps its existing behavior:
/// portrait-only during onboarding, otherwise all but upside-down. A presented view controller's
/// own mask always wins on either idiom. The single home for this rule; callers supply live values.
enum InterfaceOrientationPolicy {
    static func supportedOrientations(
        isPad: Bool,
        isShowingOnboarding: Bool,
        presentedInterfaceOrientations: UIInterfaceOrientationMask?
    ) -> UIInterfaceOrientationMask {
        if let presentedInterfaceOrientations {
            return presentedInterfaceOrientations
        }
        if isPad {
            return .all
        }
        return isShowingOnboarding ? .portrait : .allButUpsideDown
    }
}
