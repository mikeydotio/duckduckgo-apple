//
//  NewAddressBarPickerRefreshContentView.swift
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
import UIComponents
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import Onboarding

struct NewAddressBarPickerRefreshContentView: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.stackSpacing) {
                Header()
                PickerCard(viewModel: viewModel)
            }
            .frame(maxWidth: cardMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.topPadding)
            .padding(.horizontal, Metrics.horizontalPadding)
        }
        .background(BackgroundIllustration())
        .modifier(ScrollBounceBehaviorModifier())
    }

    private var cardMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? Metrics.cardMaxWidthPad : Metrics.cardMaxWidth
    }

    private enum Metrics {
        static let cardMaxWidth: CGFloat = 360
        static let cardMaxWidthPad: CGFloat = 420
        static let stackSpacing: CGFloat = 24
        static let topPadding: CGFloat = 24
        static let horizontalPadding: CGFloat = 16
    }
}

private struct Header: View {
    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Image(uiImage: DesignSystemImages.Color.Size32.duckDuckAI)

            HStack(spacing: Metrics.badgeSpacing) {
                BadgeView(text: UserText.settingsItemNewBadge)
                    .cornerRadius(Metrics.badgeCornerRadius)

                Text(UserText.newAddressBarPickerTitle)
                    .textCase(.uppercase)
                    .daxFootnoteSemibold()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
    }

    private enum Metrics {
        static let spacing: CGFloat = 12
        static let badgeSpacing: CGFloat = 8
        static let badgeCornerRadius: CGFloat = 16
    }
}

private struct PickerCard: View {
    @ObservedObject var viewModel: NewAddressBarPickerViewModel
    @Environment(\.onboardingTheme) private var onboardingTheme

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Text(UserText.newAddressBarPickerRefreshHeadline)
                .daxTitle2()
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SearchExperiencePicker(isDuckAISelected: $viewModel.isDuckAISelected)

            Text(UserText.newAddressBarPickerRefreshFooter)
                .daxFootnoteRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.confirm()
            } label: {
                Text(UserText.newAddressBarPickerConfirm)
            }
            .buttonStyle(onboardingTheme.primaryButtonStyle.style)
        }
        .padding(Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color(designSystemColor: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(Color(designSystemColor: .accent).opacity(Metrics.borderOpacity), lineWidth: 1)
        )
    }

    private enum Metrics {
        static let spacing: CGFloat = 20
        static let padding: CGFloat = 20
        static let cornerRadius: CGFloat = 16
        static let borderOpacity: CGFloat = 0.3
    }
}

private struct SearchExperiencePicker: View {
    @Binding var isDuckAISelected: Bool
    @Environment(\.onboardingTheme) private var onboardingTheme
    @State private var maxOptionTitleHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.spacing) {
            option(
                isSelected: !isDuckAISelected,
                selectedImage: OnboardingRebrandingImages.SearchExperience.searchOn,
                unselectedImage: OnboardingRebrandingImages.SearchExperience.searchOff,
                title: UserText.Onboarding.SearchExperience.searchOnlyOption
            ) { isDuckAISelected = false }

            option(
                isSelected: isDuckAISelected,
                selectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOn,
                unselectedImage: OnboardingRebrandingImages.SearchExperience.searchAIOff,
                title: UserText.Onboarding.SearchExperience.searchAndDuckAIOption
            ) { isDuckAISelected = true }
        }
        .onPreferenceChange(OptionTitleHeightPreferenceKey.self) { maxOptionTitleHeight = $0 }
    }

    private func option(isSelected: Bool, selectedImage: Image, unselectedImage: Image, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Metrics.spacing) {
                (isSelected ? selectedImage : unselectedImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: Metrics.imageHeight)

                measuredTitleBlock {
                    Text(title)
                        .font(onboardingTheme.typography.small)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: maxOptionTitleHeight, alignment: .top)

                OnboardingRebranding.RadioIndicator(
                    isSelected: isSelected,
                    accentColor: onboardingTheme.colorPalette.optionsListIconColor
                )
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func measuredTitleBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: OptionTitleHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
    }

    private enum Metrics {
        static let spacing: CGFloat = 8
        static let imageHeight: CGFloat = 72
    }
}

private struct OptionTitleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BackgroundIllustration: View {

    var body: some View {
        VStack {
            Spacer()
            OnboardingRebrandingImages.Linear.addressBarSearchPreferenceBackground
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(maxHeight: Metrics.backgroundMaxHeight)
        }
        .ignoresSafeArea()
    }

    private enum Metrics {
        static let backgroundMaxHeight: CGFloat = 294
    }
}
