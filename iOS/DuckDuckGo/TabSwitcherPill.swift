//
//  TabSwitcherPill.swift
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

import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct TabSwitcherPill: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.tabMobile)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .icons))

                if count > 0 {
                    Text(countText)
                        .font(countFont)
                        .foregroundColor(Color(designSystemColor: .icons))
                        .offset(y: isOverflow ? -Metrics.overflowYOffset : 0)
                }
            }
            .frame(width: Metrics.size, height: Metrics.size)
            .background(
                Circle()
                    .fill(Color(designSystemColor: .controlsFillSecondary))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(UserText.tabSwitcherAccessibilityLabel))
        .accessibilityValue(Text(UserText.numberOfTabs(count)))
        .accessibilityIdentifier("NTP.escapeHatch.tabSwitcher")
    }

    private var isOverflow: Bool {
        count >= Metrics.maxTextTabs
    }

    private var countText: String {
        isOverflow ? "∞" : "\(count)"
    }

    private var countFont: Font {
        let size = isOverflow ? Metrics.overflowFontSize : Metrics.fontSize
        let weight: Font.Weight = isOverflow ? .semibold : .bold
        let font = Font.system(size: size, weight: weight)
        if #available(iOS 16.0, *) {
            return font.width(.condensed)
        }
        return font
    }
}

private enum Metrics {
    static let size: CGFloat = 56
    static let maxTextTabs = 100
    static let fontSize: CGFloat = 12
    static let overflowFontSize: CGFloat = 14
    static let overflowYOffset: CGFloat = 1
}

// MARK: - Previews

#Preview("Tab switcher pill — counts") {
    HStack(spacing: 8) {
        TabSwitcherPill(count: 1, onTap: {})
        TabSwitcherPill(count: 9, onTap: {})
        TabSwitcherPill(count: 99, onTap: {})
        TabSwitcherPill(count: 100, onTap: {})
    }
    .padding()
}
