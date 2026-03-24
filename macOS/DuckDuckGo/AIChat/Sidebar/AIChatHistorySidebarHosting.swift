//
//  AIChatHistorySidebarHosting.swift
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

import AppKit
import Foundation

/// Protocol that abstracts BrowserTabViewController's left-side history container
/// so AIChatHistorySidebarCoordinator can drive layout without a direct import.
@MainActor
protocol AIChatHistorySidebarHosting: AnyObject {
    /// Trailing constraint of the history container anchored to view.leadingAnchor.
    /// constant = 0 → hidden (off left edge); constant = historyWidth → fully visible.
    var historyContainerTrailingConstraint: NSLayoutConstraint? { get }

    /// Width constraint of the history container.
    var historyContainerWidthConstraint: NSLayoutConstraint? { get }

    /// Embeds the history sidebar VC into the left container once at setup.
    func embedHistorySidebarViewController(_ viewController: NSViewController)
}

extension BrowserTabViewController: AIChatHistorySidebarHosting {

    func embedHistorySidebarViewController(_ viewController: NSViewController) {
        // Remove any previously embedded history sidebar VC
        children
            .filter { $0.view.superview === historyContainer }
            .forEach { $0.removeCompletely() }

        addAndLayoutChild(viewController, into: historyContainer)
    }
}
