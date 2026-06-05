//
//  SubscriptionOnboardingPage.swift
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
import DuckUI

struct SubscriptionOnboardingPage<Content: View>: View {

    struct Action {
        let title: String
        let perform: () -> Void
    }

    let title: Text
    let primaryButton: Action?
    let secondaryButton: Action?
    let onClose: () -> Void
    let onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        title: Text,
        primaryButton: Action? = nil,
        secondaryButton: Action? = nil,
        onClose: @escaping () -> Void,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        self.onClose = onClose
        self.onBack = onBack
        self.content = content
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(designSystemColor: .surface)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        content()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }

                    if primaryButton != nil || secondaryButton != nil {
                        VStack(spacing: 8) {
                            if let primaryButton {
                                Button(action: primaryButton.perform) {
                                    Text(primaryButton.title)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }

                            if let secondaryButton {
                                Button(action: secondaryButton.perform) {
                                    Text(secondaryButton.title)
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.backward")
                        }
                    } else {
                        Button("Close", action: onClose)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if onBack != nil {
                        Button("Close", action: onClose)
                    }
                }
            }
        }
    }
}
