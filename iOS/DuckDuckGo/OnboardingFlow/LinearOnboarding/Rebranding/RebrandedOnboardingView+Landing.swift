//
//  RebrandedOnboardingView+Landing.swift
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
import Onboarding
import Lottie

private enum LandingViewMetrics {
    static let logoSize: CGFloat = 90
    static let topPadding: CGFloat = 80
    static let welcomeBottomPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 24
    static let titleMaxWidth: CGFloat = 300
    static let illustrationHeightRatio: CGFloat = 0.62
    static let minIllustrationHeight: CGFloat = 430
    static let maxIllustrationHeight: CGFloat = 560
    static let illustrationStaticProgress: AnimationProgressTime = 0.9
    static let illustrationWidthMultiplier: CGFloat = 4.0
}

private enum LandingViewAssets {
    static let illustrationAnimation = "OnboardingLandingIllustrationAnimation"
}

extension OnboardingRebranding.OnboardingView {

    struct LandingView: View {
        @Environment(\.onboardingTheme) private var onboardingTheme

        let animationNamespace: Namespace.ID

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    welcomeView
                        .padding(.top, LandingViewMetrics.topPadding)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                    illustrationView(width: proxy.size.width, height: illustrationHeight(for: proxy.size.height))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }

        private var welcomeView: some View {
            VStack(alignment: .center, spacing: LandingViewMetrics.welcomeBottomPadding) {
                OnboardingRebrandingImages.Branding.duckDuckGoLogo
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: LandingViewMetrics.logoSize, height: LandingViewMetrics.logoSize)

                Text(UserText.onboardingWelcomeHeader)
                    .font(onboardingTheme.typography.largeTitle)
                    .foregroundStyle(onboardingTheme.colorPalette.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: LandingViewMetrics.titleMaxWidth)
            }
            .padding(.horizontal, LandingViewMetrics.horizontalPadding)
        }

        private func illustrationView(width: CGFloat, height: CGFloat) -> some View {
            LandingIllustrationContainerView(
                lottieAsset: LandingViewAssets.illustrationAnimation,
                progress: LandingViewMetrics.illustrationStaticProgress,
                widthMultiplier: LandingViewMetrics.illustrationWidthMultiplier
            )
            .frame(width: width, height: height)
            .clipped()
            .allowsHitTesting(false)
        }

        private func illustrationHeight(for screenHeight: CGFloat) -> CGFloat {
            let scaledHeight = screenHeight * LandingViewMetrics.illustrationHeightRatio
            return min(max(scaledHeight, LandingViewMetrics.minIllustrationHeight), LandingViewMetrics.maxIllustrationHeight)
        }

    }

}

private struct LandingIllustrationContainerView: UIViewRepresentable {

    let lottieAsset: String
    let progress: AnimationProgressTime
    let widthMultiplier: CGFloat

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true

        let animationView = LottieAnimationView()
        animationView.animation = LottieAnimation.asset(lottieAsset)
        animationView.contentMode = .scaleAspectFit
        animationView.currentProgress = progress
        animationView.loopMode = .playOnce
        animationView.isUserInteractionEnabled = false
        animationView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(animationView)

        let aspectRatio: CGFloat = 4000.0 / 1622.0
        NSLayoutConstraint.activate([
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            animationView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            animationView.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: widthMultiplier),
            animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor, multiplier: 1.0 / aspectRatio),
        ])

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let animationView = uiView.subviews.first as? LottieAnimationView else { return }
        if animationView.animation == nil {
            animationView.animation = LottieAnimation.asset(lottieAsset)
        }
        animationView.currentProgress = progress
    }

}
