//
//  NewTabPageNextStepsCardsPixelHandler.swift
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

import NewTabPage
import PixelExperimentKit
import PixelKit
import PrivacyConfig

protocol NewTabPageNextStepsCardsPixelHandling {

    /// Fires the next steps card shown pixels for each card in the provided list of cards, the first time the card is shown.
    /// - Parameter cards: The list of cards that were shown.
    func fireNextStepsCardShownPixels(_ cards: [NewTabPageDataModel.CardID])

    /// Fires the next steps card clicked pixel for the provided card.
    func fireNextStepsCardClickedPixel(_ card: NewTabPageDataModel.CardID)

    /// Fires the next steps card dismissed pixel for the provided card.
    func fireNextStepsCardDismissedPixel(_ card: NewTabPageDataModel.CardID)

    /// Fires the add to dock pixel if the add to dock card is present in the provided list of cards.
    /// - Parameter cards: The list of cards that were shown.
    func fireAddToDockPresentedPixelIfNeeded(_ cards: [NewTabPageDataModel.CardID])

    /// Fires the `GeneralPixel.userAddedToDockFromNewTabPageCard` pixel.
    func fireAddedToDockPixel()

    /// Fires the `GeneralPixel.defaultRequestedFromHomepageSetupView` pixel.
    func fireDefaultBrowserRequestedPixel()

    /// Fires the `SubscriptionPixel.subscriptionNewTabPageNextStepsCardClicked` pixel.
    func fireSubscriptionCardClickedPixel()

    /// Fires the `SubscriptionPixel.subscriptionNewTabPageNextStepsCardDismissed` pixel.
    func fireSubscriptionCardDismissedPixel()
}

final class NewTabPageNextStepsCardsPixelHandler: NewTabPageNextStepsCardsPixelHandling {
    private let pixelHandler: (PixelKitEvent, PixelKit.Frequency, Bool) -> Void
    private let experimentPixelHandler: ExperimentPixelFiring.Type

    private enum NextStepsCardsExperiment {
        static let conversionWindows = [Window.sevenDay, Window.fourteenDay]

        enum Metric {
            case cardShown(NewTabPageDataModel.CardID)
            case cardClicked(NewTabPageDataModel.CardID)

            var name: String {
                switch self {
                case .cardShown(let card):
                    return "\(card.rawValue)_shown"
                case .cardClicked(let card):
                    return "\(card.rawValue)_clicked"
                }
            }
        }

        enum Window {
            static let sevenDay: ConversionWindow = 0...6
            static let fourteenDay: ConversionWindow = 0...13
        }
    }

    init(pixelHandler: @escaping (PixelKitEvent, PixelKit.Frequency, Bool) -> Void = { PixelKit.fire($0, frequency: $1, includeAppVersionParameter: $2) },
         experimentPixelHandler: ExperimentPixelFiring.Type = PixelKit.self) {
        self.pixelHandler = pixelHandler
        self.experimentPixelHandler = experimentPixelHandler
    }

    func fireCardShownExperimentPixel(_ card: NewTabPageDataModel.CardID) {
        let metric = NextStepsCardsExperiment.Metric.cardShown(card).name
        for window in NextStepsCardsExperiment.conversionWindows {
            experimentPixelHandler.fireExperimentPixel(for: HtmlNewTabPageSubfeature.nextStepsListAdvancedCardOrdering.rawValue,
                                                       metric: metric,
                                                       conversionWindowDays: window,
                                                       value: "1")
        }
    }

    func fireCardClickedExperimentPixel(_ card: NewTabPageDataModel.CardID) {
        let metric = NextStepsCardsExperiment.Metric.cardClicked(card).name
        for window in NextStepsCardsExperiment.conversionWindows {
            experimentPixelHandler.fireExperimentPixel(for: HtmlNewTabPageSubfeature.nextStepsListAdvancedCardOrdering.rawValue,
                                                       metric: metric,
                                                       conversionWindowDays: window,
                                                       value: "1")
        }
    }

    func fireAddToDockPresentedPixelIfNeeded(_ cards: [NewTabPageDataModel.CardID]) {
        guard cards.contains(.addAppToDockMac) else {
            return
        }
        pixelHandler(GeneralPixel.addToDockNewTabPageCardPresented, .uniqueByName, false)
    }

    func fireNextStepsCardShownPixels(_ cards: [NewTabPageDataModel.CardID]) {
        for card in cards {
            // Fires once per card (unique by name + key parameter)
            pixelHandler(NewTabPagePixel.nextStepsCardShown(card.rawValue), .uniqueByNameAndParameters, false)
            fireCardShownExperimentPixel(card)
        }
    }

    func fireNextStepsCardClickedPixel(_ card: NewTabPage.NewTabPageDataModel.CardID) {
        pixelHandler(NewTabPagePixel.nextStepsCardClicked(card.rawValue), .standard, true)
        fireCardClickedExperimentPixel(card)
    }

    func fireNextStepsCardDismissedPixel(_ card: NewTabPage.NewTabPageDataModel.CardID) {
        pixelHandler(NewTabPagePixel.nextStepsCardDismissed(card.rawValue), .standard, true)
    }

    func fireAddedToDockPixel() {
        pixelHandler(GeneralPixel.userAddedToDockFromNewTabPageCard, .standard, false)
    }

    func fireDefaultBrowserRequestedPixel() {
        pixelHandler(GeneralPixel.defaultRequestedFromHomepageSetupView, .standard, true)
    }

    func fireSubscriptionCardClickedPixel() {
        pixelHandler(SubscriptionPixel.subscriptionNewTabPageNextStepsCardClicked, .standard, true)
    }

    func fireSubscriptionCardDismissedPixel() {
        pixelHandler(SubscriptionPixel.subscriptionNewTabPageNextStepsCardDismissed, .standard, true)
    }
}
