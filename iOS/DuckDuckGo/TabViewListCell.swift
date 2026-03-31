//
//  TabViewListCell.swift
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


import UIKit
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

final class TabViewListCell: TabViewCell {
    
    static let reuseIdentifier = "TabViewListCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
        finalizeSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setupLayout() {
        super.setupLayout()

        title.font = .daxBodySemibold()
        title.setContentHuggingPriority(.defaultLow, for: .vertical)
        title.setContentCompressionResistancePriority(.defaultHigh + 1, for: .vertical)

        let mainStack = HitTestStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        background.addSubview(mainStack)

        let faviconContainer = UIView()
        faviconContainer.translatesAutoresizingMaskIntoConstraints = false
        faviconContainer.addSubview(favicon)
        mainStack.addArrangedSubview(faviconContainer)

        let titleButtonsContainer = UIView()
        titleButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(titleButtonsContainer)

        let titleLinkStack = UIStackView()
        titleLinkStack.translatesAutoresizingMaskIntoConstraints = false
        titleLinkStack.axis = .vertical
        titleLinkStack.spacing = 2
        titleLinkStack.addArrangedSubview(title)
        titleButtonsContainer.addSubview(titleLinkStack)

        let linkLabel = FadeOutLabel()
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkLabel.font = .daxSubheadSemibold()
        linkLabel.lineBreakMode = .byClipping
        linkLabel.isAccessibilityElement = false
        linkLabel.setContentHuggingPriority(.defaultLow + 2, for: .vertical)
        titleLinkStack.addArrangedSubview(linkLabel)
        link = linkLabel

        titleButtonsContainer.addSubview(buttonContainer)

        background.addSubview(unread)

        let spacing = buttonContainer.leadingAnchor.constraint(equalTo: titleLinkStack.trailingAnchor,
                                                               constant: Constants.removeButtonTextSpacingRegular)
        textButtonSpacing = spacing

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            background.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: 12),
            mainStack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            background.bottomAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 8),
            mainStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),

            favicon.widthAnchor.constraint(equalToConstant: 24),
            favicon.heightAnchor.constraint(equalToConstant: 24),
            favicon.leadingAnchor.constraint(equalTo: faviconContainer.leadingAnchor),
            favicon.centerYAnchor.constraint(equalTo: faviconContainer.centerYAnchor),
            faviconContainer.trailingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 8),
            faviconContainer.heightAnchor.constraint(equalToConstant: 44),

            titleLinkStack.leadingAnchor.constraint(equalTo: titleButtonsContainer.leadingAnchor),
            titleLinkStack.topAnchor.constraint(equalTo: titleButtonsContainer.topAnchor, constant: 8),
            titleButtonsContainer.bottomAnchor.constraint(equalTo: titleLinkStack.bottomAnchor, constant: 8),

            buttonContainer.topAnchor.constraint(equalTo: titleButtonsContainer.topAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: titleButtonsContainer.bottomAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: titleButtonsContainer.trailingAnchor),
            spacing,

            removeButton.widthAnchor.constraint(equalToConstant: 44),
            removeButton.heightAnchor.constraint(equalToConstant: 44),
            removeButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            removeButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),

            unread.widthAnchor.constraint(equalToConstant: 10),
            unread.heightAnchor.constraint(equalToConstant: 10),
            unread.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            unread.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),
        ])
    }
}
