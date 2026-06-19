//
//  VPNStrictRoutingTip.swift
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

import DesignResourcesKitIcons
import TipKit

/// A tip that reminds the user to turn Strict routing back on after they've disabled it.
///
struct VPNStrictRoutingTip {}

@available(iOS 17.0, *)
extension VPNStrictRoutingTip: Tip {

    enum ActionIdentifiers: String {
        case enable = "com.duckduckgo.vpn.tip.strictRouting.enableId"
    }

    /// Whether the reminder is currently due. The pacing (grace period before the first
    /// appearance and the recurrence interval) is computed in `VPNTipsModel`, which keeps this
    /// parameter in sync. The rule simply mirrors it.
    @Parameter
    static var shouldShow: Bool = false

    /// Index of the current reminder interval since Strict routing was disabled. Folded into `id`
    /// so each interval is a distinct tip to TipKit — that way the permanent close button (the X)
    /// only suppresses the current occurrence, not every future one. Kept in sync by `VPNTipsModel`.
    static var currentInterval: Int = 0

    var id: String {
        "com.duckduckgo.vpn.tip.strictRouting.\(Self.currentInterval)"
    }

    var title: Text {
        Text(UserText.networkProtectionStrictRoutingTipTitle)
            .foregroundStyle(Color(designSystemColor: .textPrimary))
    }

    var message: Text? {
        Text(UserText.networkProtectionStrictRoutingTipMessage)
            .foregroundStyle(Color(designSystemColor: .textSecondary))
    }

    var image: Image? {
        Image(uiImage: DesignSystemImages.Glyphs.Size24.shield)
    }

    var actions: [Action] {
        [Action(id: ActionIdentifiers.enable.rawValue) {
            Text(UserText.networkProtectionStrictRoutingTipAction)
                .foregroundStyle(Color(designSystemColor: .buttonsPrimaryText))
        }]
    }

    var rules: [Rule] {
        #Rule(Self.$shouldShow) {
            $0
        }
    }
}
