//
//  DuckAIFloatingOmnibarWindow.swift
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

/// Floating, borderless `NSPanel` that hosts the global Duck.ai omnibar UI above other apps.
final class DuckAIFloatingOmnibarWindow: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Called by `cancelOperation` (Escape). The window controller routes this through its own
    /// close path so it can hand focus back to the previously-active app *before* AppKit gets a
    /// chance to cycle key onto another DDG window.
    var onCancelRequested: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        // `.popUpMenu` (101) sits above any normal app window level. `.nonactivatingPanel` lets the
        // panel become the system's key window without the owning app having to be foreground —
        // mirrors the pattern used by `NSStatusItem` menus and the address bar's suggestions popup,
        // and avoids pulling DDG's other windows forward when the user opens the entry point from a
        // different app.
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // NSPanel defaults this to true; when set, `makeKeyAndOrderFront` does NOT promote the panel
        // to key window — fields can't take input until the user clicks something inside. Force it
        // off so the panel becomes key the moment we order it front.
        becomesKeyOnlyIfNeeded = false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancelRequested?()
    }
}
