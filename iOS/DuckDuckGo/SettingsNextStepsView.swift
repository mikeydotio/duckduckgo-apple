//
//  SettingsNextStepsView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

struct SettingsNextStepsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var swipeColor: Color {
        switch colorScheme {
        case .light:
            Color(red: 0.875, green: 0.875, blue: 0.875)
        case .dark:
            Color(red: 0.255, green: 0.255, blue: 0.255)
        @unknown default:
            Color(red: 0.875, green: 0.875, blue: 0.875)
        }
    }

    var body: some View {
        Section(header: Text(UserText.nextSteps)) {
            // Add App to Your Dock
            if viewModel.shouldShowAddToDock {
                SettingsCellView(label: UserText.settingsAddToDock,
                                 image: Image(uiImage: DesignSystemImages.Color.Size24.addToDock),
                                 action: { viewModel.presentLegacyView(.addToDock) },
                                 isButton: true)
                .swipeActions {
                    Button {
                        viewModel.dismissAddToDock()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(swipeColor)
                }
                .id(colorScheme)
            }

            // Add Widget to Home Screen
            if viewModel.shouldShowAddWidget {
                NavigationLink(destination: WidgetEducationView()) {
                    SettingsCellView(label: UserText.settingsAddWidget,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.addWidget))
                }
                .swipeActions {
                    Button {
                        viewModel.dismissAddWidget()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(swipeColor)
                }
                .id(colorScheme)
            }

            // Set Your Address Bar Position (iPhone only)
            if viewModel.shouldShowAddressBarPosition {
                NavigationLink(destination: SettingsAppearanceView().environmentObject(viewModel)) {
                    SettingsCellView(label: UserText.setYourAddressBarPosition,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.addressBarBottom))
                }
                .swipeActions {
                    Button {
                        viewModel.dismissAddressBarPosition()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(swipeColor)
                }
                .id(colorScheme)
            }

            // Enable Voice Search
            if viewModel.shouldShowVoiceSearch {
                NavigationLink(destination: SettingsAccessibilityView().environmentObject(viewModel)) {
                    SettingsCellView(label: UserText.enableVoiceSearch,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.microphone))
                }
                .swipeActions {
                    Button {
                        viewModel.dismissVoiceSearch()
                    } label: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.eyeClosed
                            .withTintColor(UIColor(designSystemColor: .textPrimary), renderingMode: .alwaysOriginal))
                    }
                    .tint(swipeColor)
                }
                .id(colorScheme)
            }
        }
    }
}
