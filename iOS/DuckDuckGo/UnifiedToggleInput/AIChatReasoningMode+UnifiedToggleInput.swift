//
//  AIChatReasoningMode+UnifiedToggleInput.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

extension AIChatReasoningMode {
    var unifiedToggleInputTitle: String {
        switch self {
        case .fast:
            return UserText.aiChatReasoningModeFastTitle
        case .reasoning:
            return UserText.aiChatReasoningModeReasoningTitle
        case .extendedReasoning:
            return UserText.aiChatReasoningModeExtendedTitle
        }
    }

    var unifiedToggleInputSubtitle: String {
        switch self {
        case .fast:
            return UserText.aiChatReasoningModeFastSubtitle
        case .reasoning:
            return UserText.aiChatReasoningModeReasoningSubtitle
        case .extendedReasoning:
            return UserText.aiChatReasoningModeExtendedSubtitle
        }
    }

    var unifiedToggleInputMenuImage: UIImage? {
        switch self {
        case .fast:
            return DesignSystemImages.Color.Size24.lightning
        case .reasoning:
            return UIImage(systemName: "brain.head.profile")
        case .extendedReasoning:
            return UIImage(systemName: "timer")
        }
    }

    var unifiedToggleInputButtonImage: UIImage? {
        switch self {
        case .fast:
            return DesignSystemImages.Color.Size24.lightning
        case .reasoning:
            return UIImage(systemName: "brain.head.profile")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        case .extendedReasoning:
            return UIImage(systemName: "timer")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        }
    }

    var unifiedToggleInputButtonTintColor: UIColor {
        switch self {
        case .fast:
            return UIColor(designSystemColor: .iconsSecondary)
        case .reasoning:
            return UIColor(designSystemColor: .accent)
        case .extendedReasoning:
            return UIColor(designSystemColor: .alertYellow)
        }
    }
}
