//
//  DuckAIImageContextMenuUserScript.swift
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

import WebKit
import UserScript

/// Records the URL of the most recently long-pressed image so the native long-press menu can
/// offer an "Ask Duck.ai" action for it.
///
/// `WKContextMenuElementInfo` only exposes `linkURL` (no image URL and no touch coordinates),
/// so the element under a long press is resolved in JavaScript instead. iOS WKWebView does not
/// reliably dispatch a DOM `contextmenu` event on long-press, so a capture-phase `touchstart`
/// listener records the touch point at finger-down and stores the topmost `<img>` URL at that
/// point on `window.__ddg_longPressedImageURL` (or `null`). `elementsFromPoint` is used so an
/// image is still found when transparent overlays sit on top of it. `TabViewController`'s
/// `contextMenuConfigurationForElement(...)` handler reads the value via `evaluateJavaScript`.
///
/// First-cut limitations: only the main frame is observed (images inside cross-origin iframes
/// are not captured), and only `<img>` elements are resolved (CSS background images are not).
final class DuckAIImageContextMenuUserScript: NSObject, UserScript {

    /// Name of the `window` property the script writes the resolved image URL to.
    static let imageURLGlobalName = "__ddg_longPressedImageURL"

    var source: String {
        """
        (function() {
            "use strict";
            var globalName = "\(Self.imageURLGlobalName)";
            function imageURLAtPoint(x, y) {
                var stack = (document.elementsFromPoint && document.elementsFromPoint(x, y)) || [];
                for (var i = 0; i < stack.length; i++) {
                    var element = stack[i];
                    if (element && element.tagName && element.tagName.toLowerCase() === "img") {
                        return element.currentSrc || element.src || null;
                    }
                }
                return null;
            }
            function record(x, y) {
                try {
                    window[globalName] = imageURLAtPoint(x, y);
                } catch (error) {
                    window[globalName] = null;
                }
            }
            document.addEventListener("touchstart", function(event) {
                var touch = event.touches && event.touches[0];
                if (touch) {
                    record(touch.clientX, touch.clientY);
                }
            }, true);
            // Desktop/iPad pointer paths may still emit contextmenu; record there too.
            document.addEventListener("contextmenu", function(event) {
                record(event.clientX, event.clientY);
            }, true);
        })();
        """
    }

    var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    var forMainFrameOnly: Bool = true
    var messageNames: [String] = []
    var requiresRunInPageContentWorld: Bool { true }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
