//
//  AIChatState+Migration.swift
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

/// Legacy migration for `AIChatState` NSSecureCoding archives.
///
/// Earlier versions persisted two separate bools (`isPresented`, `isDetached`)
/// instead of a single `AIChatPresentationMode` enum. This helper reads
/// whichever format is present and returns the correct mode.
///
/// This file must be kept indefinitely -- users who skip the introducing
/// release would still have archives containing only the legacy bool keys.

extension AIChatState {

    static func decodePresentationMode(from coder: NSCoder) -> AIChatPresentationMode {
        if let raw = coder.decodeObject(of: NSString.self, forKey: CodingKeys.presentationMode) as? String {
            return AIChatPresentationMode(rawValue: raw) ?? .hidden
        }

        let wasPresented: Bool = coder.decodeIfPresent(at: CodingKeys.isPresented) ?? true
        let wasDetached: Bool = coder.decodeIfPresent(at: CodingKeys.isDetached) ?? false

        if wasPresented {
            return wasDetached ? .floating : .sidebar
        }
        return .hidden
    }
}
