//
//  AIChatLauncherPanel.swift
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
import SwiftUI

/// Activating NSPanel that hosts AIChatLauncherView.
/// Intercepts arrow keys and Esc for keyboard navigation.
final class AIChatLauncherPanel: NSPanel {

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let escape: UInt16 = 53
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    private enum Constants {
        static let panelSize = NSSize(width: 560, height: 540)
    }

    private let hostingController: NSHostingController<AIChatLauncherView>
    private(set) var viewModel: AIChatLauncherViewModel

    override var canBecomeKey: Bool { true }

    init(viewModel: AIChatLauncherViewModel) {
        self.viewModel = viewModel
        self.hostingController = NSHostingController(rootView: AIChatLauncherView(viewModel: viewModel))
        super.init(
            contentRect: NSRect(origin: .zero, size: Constants.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false

        // Use contentView directly instead of contentViewController to prevent
        // NSHostingController.preferredContentSize from overriding the fixed panel size.
        let hostedView = hostingController.view
        hostedView.autoresizingMask = [.width, .height]
        hostedView.frame = NSRect(origin: .zero, size: Constants.panelSize)
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hostedView
    }

    // MARK: - Keyboard Interception

    /// Override sendEvent so arrow/escape/return are intercepted before the text field
    /// (which is normally first responder) consumes them.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }
        switch event.keyCode {
        case KeyCode.downArrow:
            viewModel.moveSelectionDown()
        case KeyCode.upArrow:
            viewModel.moveSelectionUp()
        case KeyCode.returnKey:
            viewModel.submitQuery()
        case KeyCode.escape:
            viewModel.onDismiss?()
        default:
            super.sendEvent(event)
        }
    }

    // MARK: - ⌘W: hide via dismiss

    override func performClose(_ sender: Any?) {
        viewModel.onDismiss?()
    }
}
