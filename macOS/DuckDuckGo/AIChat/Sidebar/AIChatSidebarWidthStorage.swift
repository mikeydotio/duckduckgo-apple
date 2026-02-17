//
//  AIChatSidebarWidthStorage.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Persists and clamps the user-chosen AI Chat sidebar width.
protocol AIChatSidebarWidthStoring {
    var sidebarWidth: CGFloat { get set }
    var minWidth: CGFloat { get }
    var maxWidth: CGFloat { get }
}

extension AIChatSidebarWidthStoring {
    func clamped(_ width: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, width))
    }
}

final class DefaultAIChatSidebarWidthStorage: AIChatSidebarWidthStoring {

    private enum Constants {
        static let defaultWidth: CGFloat = 400
        static let minWidth: CGFloat = 300
        static let maxWidth: CGFloat = 900
        static let userDefaultsKey = "aichat.sidebar.width"
    }

    private let userDefaults: UserDefaults

    var minWidth: CGFloat { Constants.minWidth }
    var maxWidth: CGFloat { Constants.maxWidth }

    var sidebarWidth: CGFloat {
        get {
            let stored = userDefaults.double(forKey: Constants.userDefaultsKey)
            guard stored > 0 else { return Constants.defaultWidth }
            return clamped(stored)
        }
        set {
            userDefaults.set(Double(clamped(newValue)), forKey: Constants.userDefaultsKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
}
