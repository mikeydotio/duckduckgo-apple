//
//  AIChatSuggestionsView.swift
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

import AppKit
import AIChat
import Combine
import DesignResourcesKit

/// A view that displays a list of AI chat suggestions using an NSStackView.
/// Supports keyboard-based selection and mouse interaction.
final class AIChatSuggestionsView: NSView {

    private enum Constants {
        static let rowHeight: CGFloat = 32
        static let separatorHeight: CGFloat = 1
        static let separatorTopPadding: CGFloat = 0
        static let separatorBottomPadding: CGFloat = 8
        static let separatorHorizontalInset: CGFloat = 12
        static let rowsHorizontalPadding: CGFloat = 4
        static let bottomPadding: CGFloat = 4
    }

    // MARK: - UI Components

    private let separatorView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        return view
    }()

    /// Stack view for row views
    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        return stack
    }()

    /// Separator between chat rows and the "View all chats" footer.
    /// Anchored directly to self (same as top separatorView) for identical insets.
    private let viewAllChatsSeparatorView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.isHidden = true
        return view
    }()

    private lazy var viewAllChatsRow: AIChatViewAllChatsRowView = {
        let row = AIChatViewAllChatsRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isHidden = true
        row.onClick = { [weak self] in self?.onViewAllChatsClicked?() }
        row.onHoverChanged = { [weak self] isHovered in
            if isHovered { self?.boundViewModel?.clearSelection() }
        }
        return row
    }()

    // MARK: - Properties

    private var rowViews: [AIChatSuggestionRowView] = []
    private var cancellables = Set<AnyCancellable>()
    private var previousSuggestionCount: Int = 0
    private weak var boundViewModel: AIChatSuggestionsViewModel?
    private var viewTrackingArea: NSTrackingArea?

    var onSuggestionClicked: ((AIChatSuggestion) -> Void)?
    var onViewAllChatsClicked: (() -> Void)?

    /// When `true`, a "View all chats" footer row is shown below the suggestion rows.
    var showViewAllChats: Bool = false {
        didSet {
            guard oldValue != showViewAllChats else { return }
            let hasSuggestions = !rowViews.isEmpty
            separatorView.isHidden = !(hasSuggestions || showViewAllChats)
            viewAllChatsRow.isHidden = !showViewAllChats
            viewAllChatsSeparatorView.isHidden = !showViewAllChats || !hasSuggestions
        }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        addSubview(separatorView)
        addSubview(stackView)
        addSubview(viewAllChatsSeparatorView)
        addSubview(viewAllChatsRow)

        NSLayoutConstraint.activate([
            // Top separator — same 12pt inset used throughout the suggestions panel
            separatorView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.separatorTopPadding),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.separatorHorizontalInset),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.separatorHorizontalInset),
            separatorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),

            // Chat rows stack
            stackView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: Constants.separatorBottomPadding),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.rowsHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.rowsHorizontalPadding),

            // Footer separator — anchored to self with the same 12pt inset as the top separator
            viewAllChatsSeparatorView.topAnchor.constraint(equalTo: stackView.bottomAnchor),
            viewAllChatsSeparatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.separatorHorizontalInset),
            viewAllChatsSeparatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.separatorHorizontalInset),
            viewAllChatsSeparatorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),

            // Footer row — same horizontal padding as chat rows so icon/text aligns
            viewAllChatsRow.topAnchor.constraint(equalTo: viewAllChatsSeparatorView.bottomAnchor),
            viewAllChatsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.rowsHorizontalPadding),
            viewAllChatsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.rowsHorizontalPadding)
        ])

        updateSeparatorColors()
    }

    private func updateSeparatorColors() {
        NSAppearance.withAppAppearance {
            separatorView.layer?.backgroundColor = NSColor(designSystemColor: .lines).cgColor
            viewAllChatsSeparatorView.layer?.backgroundColor = NSColor.addressBarSeparator.cgColor
        }
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = viewTrackingArea {
            removeTrackingArea(existingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        viewTrackingArea = trackingArea
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        boundViewModel?.clearSelection()
        viewAllChatsRow.isHovered = false
    }

    // MARK: - Static Height Calculation

    /// Calculates the required height for a given number of suggestions.
    static func calculateHeight(forSuggestionCount count: Int, showViewAllChats: Bool = false) -> CGFloat {
        guard count > 0 || showViewAllChats else { return 0 }
        let separatorTotalHeight = Constants.separatorHeight + Constants.separatorTopPadding + Constants.separatorBottomPadding
        let rowsHeight = CGFloat(count) * Constants.rowHeight
        // Footer separator only shown when there are chat rows above it (something to separate from)
        let footerHeight: CGFloat = showViewAllChats ? (count > 0 ? Constants.separatorHeight : 0) + Constants.rowHeight : 0
        return separatorTotalHeight + rowsHeight + footerHeight + Constants.bottomPadding
    }

    // MARK: - Private Methods

    private func rebuildRows(with suggestions: [AIChatSuggestion]) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        for (index, suggestion) in suggestions.enumerated() {
            let rowView = AIChatSuggestionRowView(suggestion: suggestion)
            rowView.translatesAutoresizingMaskIntoConstraints = false

            rowView.onClick = { [weak self] in
                self?.onSuggestionClicked?(suggestion)
            }

            rowView.onMouseMoved = { [weak self] in
                self?.boundViewModel?.acknowledgeMouseMovement()
            }

            rowView.onHoverChanged = { [weak self] isHovered in
                if isHovered {
                    self?.boundViewModel?.select(at: index)
                    self?.viewAllChatsRow.isHovered = false
                }
            }

            stackView.addArrangedSubview(rowView)
            rowViews.append(rowView)

            rowView.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        let hasSuggestions = !suggestions.isEmpty

        // Top separator visible whenever the view shows any content
        separatorView.isHidden = !(hasSuggestions || showViewAllChats)

        // Footer row always visible when enabled (regardless of chat row count)
        viewAllChatsRow.isHidden = !showViewAllChats
        // Footer separator only shown when there are chat rows above it
        viewAllChatsSeparatorView.isHidden = !showViewAllChats || !hasSuggestions
    }

    private func updateSelection(_ selectedIndex: Int?, isKeyboardNavigating: Bool) {
        for (index, rowView) in rowViews.enumerated() {
            rowView.isSelected = (index == selectedIndex)
            rowView.isKeyboardNavigating = isKeyboardNavigating
            if isKeyboardNavigating {
                rowView.isHovered = false
            }
        }
    }

    // MARK: - Public Methods

    func setFooterRowKeyboardSelected(_ selected: Bool) {
        viewAllChatsRow.isSelected = selected
        if selected {
            rowViews.forEach { $0.isHovered = false }
        }
    }

    func bind(to viewModel: AIChatSuggestionsViewModel, onHeightChange: @escaping (CGFloat) -> Void) {
        cancellables.removeAll()

        boundViewModel = viewModel
        // Reset so the first emission always reports height (handles count=0 with showViewAllChats=true)
        previousSuggestionCount = -1

        viewModel.$filteredSuggestions
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestions in
                guard let self else { return }

                let countChanged = suggestions.count != self.previousSuggestionCount
                self.previousSuggestionCount = suggestions.count

                self.rebuildRows(with: suggestions)
                self.updateSelection(viewModel.selectedIndex, isKeyboardNavigating: viewModel.isKeyboardNavigating)

                if countChanged {
                    let newHeight = AIChatSuggestionsView.calculateHeight(forSuggestionCount: suggestions.count, showViewAllChats: self.showViewAllChats)
                    onHeightChange(newHeight)
                }
            }
            .store(in: &cancellables)

        viewModel.$selectedIndex
            .combineLatest(viewModel.$isKeyboardNavigating)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedIndex, isKeyboardNavigating in
                self?.updateSelection(selectedIndex, isKeyboardNavigating: isKeyboardNavigating)
            }
            .store(in: &cancellables)
    }

    // MARK: - Appearance Updates

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSeparatorColors()
    }
}
