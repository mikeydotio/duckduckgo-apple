//
//  AIModelPicker.swift
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
import AIChat

struct AIModelPicker: View {

    let models: [AIChatModel]
    let selectedModelId: String?
    let maxHeight: CGFloat?
    let onSelect: (String) -> Void

    init(
        models: [AIChatModel],
        selectedModelId: String?,
        maxHeight: CGFloat? = 240,
        onSelect: @escaping (String) -> Void
    ) {
        self.models = models
        self.selectedModelId = selectedModelId
        self.maxHeight = maxHeight
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView {
                    rows
                }
                .frame(maxHeight: maxHeight)
            } else {
                rows
            }
        }
        .background(Color(designSystemColor: .surfaceTertiary))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.08), radius: 40, x: 0, y: 20)
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(models, id: \.id) { model in
                AIModelRow(
                    model: model,
                    isSelected: model.id == selectedModelId,
                    onTap: { onSelect(model.id) }
                )
            }
        }
        .padding(8)
    }
}

private struct AIModelRow: View {

    let model: AIChatModel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            IconInfoRow(
                icon: Image(uiImage: model.menuIcon ?? UIImage()),
                title: composedTitle,
                trailingText: tierBadge
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isSelected ? Color(designSystemColor: .controlsFillPrimary) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var composedTitle: Text {
        let familyText = Text(family)
            .font(Font(UIFont.daxSubheadSemibold()))
            .foregroundColor(Color(designSystemColor: .textPrimary))
        guard let variant else { return familyText }
        let variantText = Text(" " + variant)
            .font(Font(UIFont.daxSubheadSemibold()))
            .foregroundColor(Color(designSystemColor: .textSecondary))
        return familyText + variantText
    }

    private var tierBadge: Text? {
        guard let label = tierLabel else { return nil }
        return Text(label)
            .font(Font(UIFont.daxCaptionBold()))
            .foregroundColor(Color(designSystemColor: .textTertiary))
    }

    private var family: String {
        let name = model.name
        let shortName = model.shortName
        if shortName != name && name.hasPrefix(shortName) {
            return shortName
        }
        return name
    }

    private var variant: String? {
        let name = model.name
        let shortName = model.shortName
        guard shortName != name, name.hasPrefix(shortName) else { return nil }
        let suffix = String(name.dropFirst(shortName.count)).trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? nil : suffix
    }

    private var tierLabel: String? {
        switch model.lowestPublicAccessTier {
        case .plus: return "PLUS"
        case .pro: return "PRO"
        case .free, nil: return nil
        }
    }
}

// MARK: - Previews

#Preview("Mixed tiers (Figma layout)") {
    AIModelPicker(
        models: [
            AIChatModel(id: "gpt-5.4", name: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5", shortName: "Claude", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "llama-4-maverick", name: "Llama 4 Maverick", shortName: "Llama 4", provider: .meta, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "gpt-5.2", name: "GPT-5.2", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", shortName: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", shortName: "Claude", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "mistral-small-4", name: "Mistral Small 4", shortName: "Mistral", provider: .mistral, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
        ],
        selectedModelId: "gpt-5.4",
        onSelect: { _ in }
    )
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("Premium only") {
    AIModelPicker(
        models: [
            AIChatModel(id: "gpt-5.4", name: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "claude-opus", name: "Claude Opus", shortName: "Claude", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["pro"])
        ],
        selectedModelId: nil,
        onSelect: { _ in }
    )
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("Free only") {
    AIModelPicker(
        models: [
            AIChatModel(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", shortName: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "mistral-small", name: "Mistral Small", shortName: "Mistral", provider: .mistral, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
        ],
        selectedModelId: "gpt-5.4-mini",
        onSelect: { _ in }
    )
    .padding()
    .background(Color(designSystemColor: .surface))
}

#Preview("Long scrollable list") {
    AIModelPicker(
        models: (1...15).map { i in
            AIChatModel(
                id: "model-\(i)",
                name: "Model \(i)",
                provider: .openAI,
                supportsImageUpload: false,
                entityHasAccess: true,
                accessTier: i % 2 == 0 ? ["plus"] : ["free"]
            )
        },
        selectedModelId: "model-3",
        onSelect: { _ in }
    )
    .padding()
    .background(Color(designSystemColor: .surface))
}
