//
//  AIChatHistorySidebarView.swift
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
import AppKit
import SwiftUI

struct AIChatHistorySidebarView: View {

    @ObservedObject var viewModel: AIChatHistorySidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            actionRows
            chatsSection
            Spacer(minLength: 0)
            Divider()
            footerView
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(nsImage: DesignSystemImages.Glyphs.Size16.aiChat)
                .renderingMode(.template)
                .foregroundColor(.primary)
                .frame(width: 20, height: 20)
            Text(UserText.aiChatHistorySidebarTitle)
                .font(.headline)
            Spacer()
            Button {
                viewModel.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Action Rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                title: UserText.aiChatHistorySidebarNewChat,
                icon: Image(nsImage: DesignSystemImages.Glyphs.Size16.aiChatAdd),
                action: { viewModel.onNewChat?() }
            )
            actionRow(
                title: UserText.aiChatHistorySidebarNewVoiceChat,
                icon: Image(nsImage: DesignSystemImages.Glyphs.Size16.permissionMicrophone),
                action: { viewModel.onNewVoiceChat?() }
            )
            actionRow(
                title: UserText.aiChatHistorySidebarNewImage,
                icon: Image(nsImage: DesignSystemImages.Glyphs.Size16.image),
                action: { viewModel.onNewImageChat?() }
            )
        }
        .padding(.vertical, 4)
    }

    private func actionRow(title: String, icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chats Section

    private var chatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(UserText.aiChatHistorySidebarChatsHeader)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            chatListContent
        }
    }

    @ViewBuilder
    private var chatListContent: some View {
        if viewModel.isLoading && viewModel.chats.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if !viewModel.isLoading && viewModel.chats.isEmpty {
            Text(UserText.aiChatHistorySidebarNoChats)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .multilineTextAlignment(.center)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.chats) { suggestion in
                        chatRow(suggestion)
                    }
                }
            }
        }
    }

    private func chatRow(_ suggestion: AIChatSuggestion) -> some View {
        Button {
            viewModel.onChatSelected?(suggestion.chatId)
        } label: {
            HStack(spacing: 8) {
                Text(suggestion.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if suggestion.isPinned {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.pin)
                        .renderingMode(.template)
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerView: some View {
        Button {
            viewModel.onSettings?()
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.aiChatSettings)
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text(UserText.aiChatHistorySidebarSettingsAndMore)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
