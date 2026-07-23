//
//  NewWindowUserActivity.swift
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

/// Carries a URL into a newly-activated scene (⌘⌥N, tab/link "Open in New Window"), via
/// `UIApplication.requestSceneSessionActivation(_:userActivity:options:)` — the only channel that
/// API offers for handing a brand-new scene any state of the caller's choosing. Must be declared
/// under `NSUserActivityTypes` in both Info.plist variants for the system to deliver it.
enum NewWindowUserActivity {

    static let activityType = "com.duckduckgo.mobile.ios.openURLInNewWindow"
    private static let urlKey = "url"

    static func make(url: URL?) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.userInfo = url.map { [urlKey: $0] }
        return activity
    }

    /// Returns the URL to open if `userActivity` is one of ours, `nil` otherwise (including when
    /// it's ours but was a blank "new window" request with no URL attached).
    static func url(from userActivity: NSUserActivity) -> URL? {
        guard userActivity.activityType == activityType else { return nil }
        return userActivity.userInfo?[urlKey] as? URL
    }

}
