//
//  UIApplicationExtension.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Subscription
import Core

extension UIApplication {

    enum TerminationError: Error {

        case insufficientDiskSpace
        case unrecoverableState

    }

    // MARK: notification settings

    private static let notificationSettingsURL: URL? = {
        let settingsString: String
        if #available(iOS 16, *) {
            settingsString = UIApplication.openNotificationSettingsURLString
        } else if #available(iOS 15.4, *) {
            settingsString = UIApplicationOpenNotificationSettingsURLString
        } else {
            settingsString = UIApplication.openSettingsURLString
        }
        return URL(string: settingsString)
    }()

    func openAppNotificationSettings() async -> Bool {
        guard
            let url = UIApplication.notificationSettingsURL,
            self.canOpenURL(url) else { return false }
        return await self.open(url)
    }

    // MARK: foreground scene windows

    var foregroundSceneWindows: [UIWindow] {
        guard let scene = UIApplication.shared.connectedScenes.first(where: {
            $0.activationState != .background
        }) as? UIWindowScene else {
            return []
        }

        return scene.windows
    }

    var firstKeyWindow: UIWindow? {
        return foregroundSceneWindows.first(where: \.isKeyWindow)
    }

    // MARK: multi-window (iPad)

    /// Requests a new, independent app window/scene (⌘⌥N, tab/link "Open in New Window"). Passing
    /// `sceneSession: nil` asks the system for a brand-new scene rather than reactivating an
    /// existing one. `url`, when given, is delivered to the new scene as a `NewWindowUserActivity`
    /// — the only channel `requestSceneSessionActivation` offers for handing a brand-new scene any
    /// state — and opened there as its first tab; `nil` yields a plain, empty new window.
    /// A no-op on iPhone, which never offers multi-window at the OS level regardless of this call.
    func requestNewWindow(opening url: URL? = nil) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        requestSceneSessionActivation(nil, userActivity: NewWindowUserActivity.make(url: url), options: nil) { error in
            Logger.lifecycle.error("🔴 Failed to activate a new window: \(error.localizedDescription, privacy: .public)")
        }
    }

}
