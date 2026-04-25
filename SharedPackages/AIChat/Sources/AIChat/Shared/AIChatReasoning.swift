//
//  AIChatReasoning.swift
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

public enum AIChatReasoningEffort: String, Codable, Equatable {
    case none
    case minimal
    case low
    case medium
    case high
}

public enum AIChatReasoningMode: String, CaseIterable, Codable, Equatable {
    case fast
    case reasoning
    case extendedReasoning = "extended_reasoning"
}

public extension AIChatModel {
    var availableReasoningModes: [AIChatReasoningMode] {
        reasoningModeMappings.map { $0.mode }
    }

    var supportsReasoningPicker: Bool {
        availableReasoningModes.count > 1
    }

    func resolvedReasoningMode(from preferredMode: AIChatReasoningMode?) -> AIChatReasoningMode? {
        let modes = availableReasoningModes
        guard !modes.isEmpty else { return nil }
        guard let preferredMode else { return modes.first }
        if modes.contains(preferredMode) { return preferredMode }

        return modes[min(preferredMode.preferredIndex, modes.count - 1)]
    }

    func reasoningEffort(for preferredMode: AIChatReasoningMode?) -> AIChatReasoningEffort? {
        guard let mode = resolvedReasoningMode(from: preferredMode) else { return nil }

        return reasoningModeMappings.first { $0.mode == mode }?.effort
    }
}

private extension AIChatModel {
    var reasoningModeMappings: [(mode: AIChatReasoningMode, effort: AIChatReasoningEffort)] {
        AIChatReasoningMode.allCases.compactMap { mode in
            guard let effort = firstSupportedReasoningEffort(in: mode.supportedEfforts) else { return nil }
            return (mode, effort)
        }
    }

    func firstSupportedReasoningEffort(in candidates: [AIChatReasoningEffort]) -> AIChatReasoningEffort? {
        candidates.first { supportedReasoningEffort.contains($0) }
    }
}

private extension AIChatReasoningMode {
    var supportedEfforts: [AIChatReasoningEffort] {
        switch self {
        case .fast:
            return [.none, .minimal]
        case .reasoning:
            return [.low]
        case .extendedReasoning:
            return [.high, .medium]
        }
    }

    var preferredIndex: Int {
        switch self {
        case .fast:
            return 0
        case .reasoning:
            return 1
        case .extendedReasoning:
            return 2
        }
    }
}
