//
//  DuckAIOnboardingActivationView.swift
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
import UIKit
import WebKit
import DesignResourcesKit
import DuckUI
import AIChat
import Subscription

struct DuckAIOnboardingActivationView: View {

    @StateObject private var viewModel: DuckAIOnboardingActivationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingChat = false

    private static let duckAIURLString = "https://duck.ai"

    init(viewModel: DuckAIOnboardingActivationViewModel = DuckAIOnboardingActivationViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if isShowingChat {
                DuckAIChatWebScreen(urlString: Self.duckAIURLString) {
                    isShowingChat = false
                }
            } else {
                onboardingContent
            }
        }
        .task {
            await viewModel.fetchModels()
        }
    }

    private var onboardingContent: some View {
        ZStack {
            Color(designSystemColor: .surface)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SubscriptionOnboardingStepHeader(step: 4, totalSteps: 4) { dismiss() }

                ScrollView {
                    VStack(spacing: 24) {
                        SettingsDescriptionView(content: headerContent)
                        modelList
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }

                footer
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var headerContent: SettingsDescription {
        SettingsDescription(
            image: UIImage(named: "DuckAI-DDG-Hero") ?? UIImage(),
            title: "Duck.ai Private Chat",
            status: nil,
            explanation: "Your subscription unlocks premium models. Chats are anonymized by us and never used to train AI. Pick one to start chatting. [Learn More](https://duckduckgo.com/pro)"
        )
    }

    private var modelList: some View {
        VStack(spacing: 4) {
            ForEach(viewModel.availableModels, id: \.id) { model in
                Button {
                    viewModel.select(model.id)
                } label: {
                    modelRow(model)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(designSystemColor: .surface))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(designSystemColor: .lines), lineWidth: 1)
        )
    }

    private func modelRow(_ model: AIChatModel) -> some View {
        HStack(spacing: 12) {
            if let icon = model.menuIcon {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .icons))
            }

            Text(model.name)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.id == viewModel.selectedModelId
                    ? Color(designSystemColor: .controlsFillSecondary)
                    : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                isShowingChat = true
            } label: {
                Text("Start Duck.ai chat")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                dismiss()
            } label: {
                Text("Not Now")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }
}

struct DuckAIChatWebScreen: View {

    let urlString: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color(designSystemColor: .surface)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { onBack() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                DuckAIWebView(urlString: urlString)
            }
        }
    }
}

struct DuckAIWebView: UIViewRepresentable {

    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

final class DuckAIOnboardingActivationViewModel: ObservableObject {

    @Published private(set) var models: [AIChatModel] = []
    @Published private(set) var selectedModelId: String?

    private let isLive: Bool
    private var modelStore: UTIModelStore?

    var selectedModel: AIChatModel? {
        models.first { $0.id == selectedModelId }
    }

    var availableModels: [AIChatModel] {
        models.filter { model in
            guard model.entityHasAccess else { return false }
            switch model.lowestPublicAccessTier {
            case .plus, .pro: return true
            default: return false
            }
        }
    }

    init(previewModels: [AIChatModel], selectedModelId: String? = nil) {
        self.models = previewModels
        self.selectedModelId = selectedModelId
        self.isLive = false
    }

    init() {
        self.isLive = true
    }

    @MainActor
    func fetchModels() async {
        guard isLive else { return }
        let store = modelStore ?? UTIModelStore(
            modelsService: AIChatModelsService(),
            preferences: AIChatPreferencesPersistor(),
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager)
        modelStore = store
        store.onModelsUpdated = { [weak self] in
            guard let self else { return }
            self.models = store.models
            self.selectedModelId = store.persistedModelId
        }
        store.fetchModels()
    }

    func select(_ modelId: String) {
        selectedModelId = modelId
        Task { @MainActor in
            self.modelStore?.updateSelectedModel(modelId, isNewChatContext: true)
        }
    }
}

#Preview("Duck.ai") {
    DuckAIOnboardingActivationView(viewModel: DuckAIOnboardingActivationViewModel(
        previewModels: [
            AIChatModel(id: "gpt-5.4-nano", name: "GPT-5.4 Nano", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "gpt-5.4-mini", name: "GPT-5.4 Mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "gpt-oss-120b", name: "gpt-oss 120B", provider: .oss, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
            AIChatModel(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "mistral-small-4", name: "Mistral Small 4", provider: .mistral, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
            AIChatModel(id: "llama-4-scout", name: "Llama 4 Scout", provider: .meta, supportsImageUpload: false, entityHasAccess: true, accessTier: ["pro"])
        ],
        selectedModelId: "claude-haiku-4.5"))
}
