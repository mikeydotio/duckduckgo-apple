//
//  FullScreenVideoUserScript.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

public protocol FullScreenVideoUserScriptDelegate: AnyObject {
    func fullScreenVideoUserScript(_ script: FullScreenVideoUserScript, didChangePictureInPictureState isActive: Bool)
}

public class FullScreenVideoUserScript: NSObject, UserScript {
    private enum MessageNames {
        static let pictureInPictureState = "pictureInPictureState"
    }

    public var source: String {
        do {
            return try Self.loadJS("fullscreenvideo", from: Bundle.core)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to load JS for FullScreenVideoUserScript: \(error)")
        }
    }

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public var forMainFrameOnly: Bool = false
    public var messageNames: [String] = [MessageNames.pictureInPictureState]
    public var requiresRunInPageContentWorld: Bool { true }
    public weak var delegate: FullScreenVideoUserScriptDelegate?

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == MessageNames.pictureInPictureState,
              let body = message.body as? [String: Any],
              let isActive = body["isActive"] as? Bool else {
            return
        }

        delegate?.fullScreenVideoUserScript(self, didChangePictureInPictureState: isActive)
    }
}
