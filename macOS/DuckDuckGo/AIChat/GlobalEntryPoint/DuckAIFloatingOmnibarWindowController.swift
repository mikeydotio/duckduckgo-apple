//
//  DuckAIFloatingOmnibarWindowController.swift
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

/// Owns the global Duck.ai floating omnibar window. M3 hosts a placeholder view; M5
/// swaps it for the real `AIChatOmnibarContainerViewController`.
@MainActor
final class DuckAIFloatingOmnibarWindowController: NSObject, NSWindowDelegate {

    private enum Constants {
        static let width: CGFloat = 580
        static let placeholderHeight: CGFloat = 80
        static let cornerRadius: CGFloat = 16
        /// Fraction of the visible screen height where the panel's top edge anchors.
        /// 1/3 = "centered ~third from the top", matching ChatGPT/Claude desktop apps.
        static let topInsetFraction: CGFloat = 1.0 / 3.0
    }

    private var window: DuckAIFloatingOmnibarWindow?
    /// When the panel is closed because it lost key status (e.g. status-bar click), AppKit
    /// dispatches `windowDidResignKey` *before* the click action that triggered it lands on
    /// `toggle()`. Without this debounce, the toggle would see `isVisible == false` and re-open
    /// the panel — flipping a "close" gesture into a "leave open" no-op.
    private var lastResignKeyCloseAt: Date?
    private static let resignKeyToggleSuppression: TimeInterval = 0.25

    var isVisible: Bool { window?.isVisible == true }

    func toggle() {
        if isVisible {
            close()
            return
        }
        if let lastClose = lastResignKeyCloseAt,
           Date().timeIntervalSince(lastClose) < Self.resignKeyToggleSuppression {
            lastResignKeyCloseAt = nil
            return
        }
        show()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        positionWindow(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Dismiss as soon as focus moves elsewhere — matches the dismiss-on-outside-click
        // expectation of a Spotlight-style entry point.
        guard let window, notification.object as AnyObject === window, window.isVisible else { return }
        lastResignKeyCloseAt = Date()
        window.close()
    }

    // MARK: - Private

    private func makeWindow() -> DuckAIFloatingOmnibarWindow {
        let initialFrame = NSRect(x: 0, y: 0, width: Constants.width, height: Constants.placeholderHeight)
        let window = DuckAIFloatingOmnibarWindow(contentRect: initialFrame)
        window.delegate = self
        window.contentView = makePlaceholderContentView()
        return window
    }

    private func makePlaceholderContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Constants.width, height: Constants.placeholderHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = Constants.cornerRadius
        container.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "Duck.ai")
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func positionWindow(_ window: NSWindow) {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        guard visible.width > 0 else { return }

        let size = window.frame.size
        let originX = visible.midX - size.width / 2
        let originY = visible.maxY - visible.height * Constants.topInsetFraction - size.height
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
