//
//  TabViewGridCell.swift
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

final class TabViewGridCell: TabViewCell {
    
    static let reuseIdentifier = "TabViewGridCell"

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

        title.font = .daxFootnoteSemibold()

        let headerStack = HitTestStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .horizontal
        background.addSubview(headerStack)

        let faviconContainer = UIView()
        faviconContainer.translatesAutoresizingMaskIntoConstraints = false
        faviconContainer.addSubview(favicon)
        faviconContainer.addSubview(unread)
        headerStack.addArrangedSubview(faviconContainer)
        headerStack.addArrangedSubview(title)

        background.addSubview(buttonContainer)

        let previewClipView = UIView()
        previewClipView.translatesAutoresizingMaskIntoConstraints = false
        previewClipView.clipsToBounds = true
        background.addSubview(previewClipView)

        let previewImageView = UIImageView()
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.clipsToBounds = true
        previewClipView.addSubview(previewImageView)
        preview = previewImageView

        let spacing = buttonContainer.leadingAnchor.constraint(equalTo: headerStack.trailingAnchor,
                                                               constant: Constants.removeButtonTextSpacingRegular)
        textButtonSpacing = spacing

        let pvTop = previewImageView.topAnchor.constraint(equalTo: previewClipView.topAnchor)
        let pvBottom = previewClipView.bottomAnchor.constraint(equalTo: previewImageView.bottomAnchor)
        let pvTrailing = previewClipView.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor)
        previewTopConstraint = pvTop
        previewBottomConstraint = pvBottom
        previewTrailingConstraint = pvTrailing

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: background.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 44),

            favicon.widthAnchor.constraint(equalToConstant: 16),
            favicon.heightAnchor.constraint(equalToConstant: 16),
            favicon.leadingAnchor.constraint(equalTo: faviconContainer.leadingAnchor, constant: 12),
            favicon.centerYAnchor.constraint(equalTo: faviconContainer.centerYAnchor),
            faviconContainer.trailingAnchor.constraint(equalTo: favicon.trailingAnchor, constant: 8),

            unread.widthAnchor.constraint(equalToConstant: 9),
            unread.heightAnchor.constraint(equalToConstant: 9),
            unread.centerYAnchor.constraint(equalTo: favicon.centerYAnchor, constant: 7),
            unread.centerXAnchor.constraint(equalTo: favicon.centerXAnchor, constant: 7),

            buttonContainer.widthAnchor.constraint(equalToConstant: 44),
            buttonContainer.heightAnchor.constraint(equalToConstant: 44),
            buttonContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            buttonContainer.centerYAnchor.constraint(equalTo: headerStack.centerYAnchor),
            spacing,

            removeButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            removeButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            removeButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            removeButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),

            previewClipView.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            previewClipView.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            previewClipView.widthAnchor.constraint(equalTo: background.widthAnchor, constant: -8),
            background.bottomAnchor.constraint(equalTo: previewClipView.bottomAnchor, constant: 4),

            pvTop,
            previewImageView.leadingAnchor.constraint(equalTo: previewClipView.leadingAnchor),
            pvBottom,
            pvTrailing,
        ])
    }
}
