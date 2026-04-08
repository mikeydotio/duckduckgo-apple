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

public enum AIChatReasoningMode: String, Codable, Equatable {
    case fast
    case reasoning
    case extendedReasoning = "extended_reasoning"
}

public extension AIChatModel {
    var availableReasoningModes: [AIChatReasoningMode] {
        reasoningModeMappings.map { $0.mode }
    }

    var supportsReasoningPicker: Bool {
        !availableReasoningModes.isEmpty
    }

    func resolvedReasoningMode(from preferredMode: AIChatReasoningMode?) -> AIChatReasoningMode? {
        let modes = availableReasoningModes
        guard !modes.isEmpty else { return nil }
        guard let preferredMode else { return modes.first }

        return modes[min(preferredMode.preferredIndex, modes.count - 1)]
    }

    func reasoningEffort(for preferredMode: AIChatReasoningMode?) -> AIChatReasoningEffort? {
        guard let mode = resolvedReasoningMode(from: preferredMode) else { return nil }

        return reasoningModeMappings.first { $0.mode == mode }?.effort
    }
}

private extension AIChatModel {
    var reasoningModeMappings: [(mode: AIChatReasoningMode, effort: AIChatReasoningEffort)] {
        guard let fastEffort = firstSupportedReasoningEffort(in: [.none, .minimal]),
              let reasoningEffort = firstSupportedReasoningEffort(in: [.low, .medium, .high]) else {
            return []
        }

        var mappings: [(mode: AIChatReasoningMode, effort: AIChatReasoningEffort)] = [
            (.fast, fastEffort),
            (.reasoning, reasoningEffort)
        ]

        if let extendedReasoningEffort = extendedReasoningEffort(after: reasoningEffort) {
            mappings.append((.extendedReasoning, extendedReasoningEffort))
        }

        return mappings
    }

    func firstSupportedReasoningEffort(in candidates: [AIChatReasoningEffort]) -> AIChatReasoningEffort? {
        candidates.first { supportedReasoningEffort.contains($0) }
    }

    func extendedReasoningEffort(after reasoningEffort: AIChatReasoningEffort) -> AIChatReasoningEffort? {
        [.high, .medium]
            .filter { supportedReasoningEffort.contains($0) }
            .first { $0 != reasoningEffort }
    }
}

private extension AIChatReasoningMode {
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
