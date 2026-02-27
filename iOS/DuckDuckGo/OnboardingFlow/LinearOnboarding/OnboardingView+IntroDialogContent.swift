//
//  OnboardingView+IntroDialogContent.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import DuckUI
import Onboarding

extension OnboardingView {

    struct IntroDialogContent: View {

        private let title: String
        private let shouldShowSkipOnboardingButton: Bool
        private var animateText: Binding<Bool>
        private var showCTA: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let continueAction: () -> Void
        private let skipAction: () -> Void

        init(
            title: String,
            shouldShowSkipOnboardingButton: Bool,
            animateText: Binding<Bool> = .constant(true),
            showCTA: Binding<Bool> = .constant(false),
            isSkipped: Binding<Bool>,
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.title = title
            self.shouldShowSkipOnboardingButton = shouldShowSkipOnboardingButton
            self.animateText = animateText
            self.showCTA = showCTA
            self.isSkipped = isSkipped
            self.continueAction = continueAction
            self.skipAction = skipAction
        }

        var body: some View {
            introContent
        }

        private var introContent: some View {
            VStack(spacing: 24.0) {
                AnimatableTypingText(title, startAnimating: animateText, skipAnimation: isSkipped) {
                    withAnimation {
                        showCTA.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))

                VStack {
                    Button(action: continueAction) {
                        Text(UserText.Onboarding.Intro.continueCTA)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if shouldShowSkipOnboardingButton {
                        OnboardingBorderedButton(maxHeight: 50.0, content: {
                            Text(UserText.Onboarding.Intro.skipCTA)
                        }, action: {
                            skipAction()
                        })
                    }
                }
                .visibility(showCTA.wrappedValue ? .visible : .invisible)
            }
        }

    }
}
