//
//  UnifiedToggleInputGrantStore.swift
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

import Foundation
import Persistence

/// Persists whether this device has ever been granted the Unified Toggle Input.
///
/// The grant is forward-only: once recorded it is never cleared, so the remote
/// `unifiedToggleInputIncludeNewUsers` lever can stop *new* users receiving UTI without ever
/// revoking it from anyone who already has it.
protocol UnifiedToggleInputGrantStoring {
    var hasGrantedUnifiedToggleInput: Bool { get }
    func recordGrant()
}

struct UnifiedToggleInputGrantStore: UnifiedToggleInputGrantStoring {

    private enum Key {
        static let hasGranted = "com.duckduckgo.unifiedToggleInput.hasGranted"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var hasGrantedUnifiedToggleInput: Bool {
        (try? keyValueStore.object(forKey: Key.hasGranted) as? Bool) ?? false
    }

    func recordGrant() {
        try? keyValueStore.set(true, forKey: Key.hasGranted)
    }
}
