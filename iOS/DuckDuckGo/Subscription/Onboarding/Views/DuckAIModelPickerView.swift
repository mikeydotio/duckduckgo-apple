//
//  DuckAIModelPickerView.swift
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
import UIComponents
import AIChat

/// The Duck.ai model picker: every available model is a row in a single `SubscriptionOnboardingCard`,
/// with a "PLUS" marker on premium models and a checkmark on the selected one. The model list comes from
/// a backend call (`AIChatModelsService`) performed at the screen layer, so this view takes the resolved
/// `AIChatModel`s, the selected id, and a selection callback — it holds no state and makes no network
/// calls itself.
struct DuckAIModelPickerView: View {
    private let models: [AIChatModel]
    private let selectedModelID: String?
    private let onSelect: (String) -> Void

    init(models: [AIChatModel], selectedModelID: String?, onSelect: @escaping (String) -> Void) {
        self.models = models
        self.selectedModelID = selectedModelID
        self.onSelect = onSelect
    }

    var body: some View {
        SubscriptionOnboardingCard(cardItems, style: .borderless, padding: 14, onSelect: handleSelection)
    }

    private var cardItems: [CardItem] {
        models.map { model in
            let nameParts = model.name.split(separator: " ", maxSplits: 1)
            let title = nameParts.first.map(String.init) ?? model.name

            var details: [CardItemTitleDetail] = []
            if nameParts.count > 1 {
                details.append(CardItemTitleDetail(text: String(nameParts[1]), font: .bodyRegular))
            }
            if model.isAdvanced {
                details.append(CardItemTitleDetail(text: UserText.subscriptionOnboardingDuckAIPlusMarker, font: .footnoteRegular))
            }

            return CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: icon(for: model), size: .size24),
                title: title,
                titleFont: .bodyRegular,
                titleDetails: details,
                trailing: model.id == selectedModelID ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil,
                accessibilityValue: model.id == selectedModelID ? UserText.subscriptionOnboardingDuckAIModelSelectedValue : nil)
        }
    }

    private func handleSelection(_ index: Int) {
        guard models.indices.contains(index) else { return }
        onSelect(models[index].id)
    }

    private func icon(for model: AIChatModel) -> CardVisual {
        if let menuIcon = model.menuIcon {
            return .image(Image(uiImage: menuIcon))
        }
        return .image(Image(systemName: "sparkles"))
    }
}

#if DEBUG

private struct DuckAIModelPickerPreviewHost: View {
    @State private var selection: String? = "claude-sonnet"

    var body: some View {
        ScrollView {
            DuckAIModelPickerView(models: previewModels, selectedModelID: selection) { selection = $0 }
                .padding()
        }
        .background(Color(designSystemColor: .background).ignoresSafeArea())
    }
}

private let previewModels: [AIChatModel] = [
    AIChatModel(id: "gpt-4o-mini", name: "GPT-4o mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
    AIChatModel(id: "llama-3.3", name: "Llama 3.3", provider: .meta, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
    AIChatModel(id: "claude-sonnet", name: "Claude Sonnet", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
    AIChatModel(id: "gpt-4o", name: "GPT-4o", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
]

#Preview("Light") {
    RebrandedPreview {
        DuckAIModelPickerPreviewHost()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        DuckAIModelPickerPreviewHost()
    }
    .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    RebrandedPreview {
        DuckAIModelPickerPreviewHost()
    }
    .dynamicTypeSize(.accessibility5)
}

#endif
