//
//  TabSwitcherPageViewController.swift
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
import Common
import FoundationExtensions
import Core
import DDGSync
import WebKit
import Bookmarks
import Persistence
import os.log
import SwiftUI
import Combine
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit
import PrivacyConfig
import AIChat
import UIComponents

protocol TabSwitcherPageDelegate: AnyObject {
    func page(_ page: TabSwitcherPageViewController, didSelectTabAt index: Int)
    func page(_ page: TabSwitcherPageViewController, didDeselectTab: Void)
    func page(_ page: TabSwitcherPageViewController, willDeleteTabs tabs: [Tab], allDeleted: Bool)
    func pageDidDeleteTabs(_ page: TabSwitcherPageViewController, allDeleted: Bool)
    func page(_ page: TabSwitcherPageViewController, didReorderTabs: Void)
    func page(_ page: TabSwitcherPageViewController, contextMenuForTabsAt indexPaths: [IndexPath]) -> UIMenu?
    // 🟣 redundant comment - remove later
    /// Long-press menu while searching. Resolved by `Tab` object (not index) because the
    /// collection shows a filtered view; offers the safe subset of actions.
    func page(_ page: TabSwitcherPageViewController, searchContextMenuForTab tab: Tab) -> UIMenu?
    func pageDidRequestDismiss(_ page: TabSwitcherPageViewController)
    func pageCellDidBeginSwipe(_ page: TabSwitcherPageViewController)
    func pageCellDidEndSwipe(_ page: TabSwitcherPageViewController)
    func pageCellDidBeginDrag(_ page: TabSwitcherPageViewController)
    func pageCellDidEndDrag(_ page: TabSwitcherPageViewController)
    /// The user started dragging the results list while searching — used to dismiss the keyboard.
    func pageDidScrollSearchResults(_ page: TabSwitcherPageViewController)

    var isEditing: Bool { get }
    var isProcessingUpdates: Bool { get set }
    var canDismissOnEmpty: Bool { get }
}

class TabSwitcherPageViewController: UIViewController {
    
    private(set) var collectionView: UICollectionView!
    let tabsModel: TabsModelManaging
    weak var pageDelegate: TabSwitcherPageDelegate?
    var onNewFireTab: (() -> Void)?
    var currentSelection: Int?


    private let browsingMode: BrowsingMode
    private weak var previewsSource: TabPreviewsSource?
    private let tabSwitcherSettings: TabSwitcherSettings
    private var isFireModeEnabled: Bool
    private var tabObserverCancellable: AnyCancellable?
    private var trackerCountViewModel: TabSwitcherTrackerCountViewModel?
    private var trackerCountCancellable: AnyCancellable?
    private var lastAppliedTrackerCountState: TabSwitcherTrackerCountViewModel.State?
    private var trackerInfoModel: InfoPanelView.Model?
    private var fireModeEmptyStateHostingController: UIHostingController<FireModeEmptyStateView>?
    private let duckAIGridContentProvider: DuckAIGridContentProviding?

    var canUpdateCollection = true

    // 🟣 redundant comment - remove later - or rather update, swipe & context menu are updated
    // Non-mutating, presentation-only filtering. `tabsModel` stays the full source of
    // truth; while searching, the collection view reads from `filteredTabs` (a derived
    // copy) instead. Mutating interactions (reorder, swipe-to-delete, context menu) are
    // disabled while searching so filtered indices never have to be translated back into
    // model indices for membership/order changes.
    private(set) var isSearchActive = false
    private var searchQuery = ""
    private var filteredTabs: [Tab] = []

    var selectedIndexPaths: [IndexPath] {
        collectionView.indexPathsForSelectedItems ?? []
    }

    init(browsingMode: BrowsingMode,
         tabsModel: TabsModelManaging,
         previewsSource: TabPreviewsSource,
         tabSwitcherSettings: TabSwitcherSettings,
         trackerCountViewModel: TabSwitcherTrackerCountViewModel?,
         isFireModeEnabled: Bool,
         duckAIGridContentProvider: DuckAIGridContentProviding?) {
        self.browsingMode = browsingMode
        self.tabsModel = tabsModel
        self.previewsSource = previewsSource
        self.tabSwitcherSettings = tabSwitcherSettings
        self.trackerCountViewModel = trackerCountViewModel
        self.isFireModeEnabled = isFireModeEnabled
        self.currentSelection = tabsModel.currentIndex
        self.duckAIGridContentProvider = duckAIGridContentProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 14
        layout.minimumInteritemSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = true
        collectionView.isMultipleTouchEnabled = true
        if #available(iOS 17.0, *) {
            collectionView.allowsKeyboardScrolling = false
        }
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsMultipleSelectionDuringEditing = true

        collectionView.register(TabViewGridCell.self, forCellWithReuseIdentifier: TabViewGridCell.reuseIdentifier)
        collectionView.register(TabViewListCell.self, forCellWithReuseIdentifier: TabViewListCell.reuseIdentifier)
        collectionView.register(
            TabSwitcherTrackerInfoHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: TabSwitcherTrackerInfoHeaderView.reuseIdentifier
        )

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let backgroundView = UIView(frame: collectionView.frame)
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(gesture:))))
        collectionView.backgroundView = backgroundView
        
        subscribeToTabChanges()
        bindTrackerCount()
        trackerCountViewModel?.refresh()
        setupFireModeEmptyState()
    }

    private var lastLayoutSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let currentSize = view.bounds.size
        guard currentSize != lastLayoutSize, currentSize != .zero else { return }
        lastLayoutSize = currentSize
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        trackerCountViewModel?.refresh()
    }
    
    private func subscribeToTabChanges() {
        tabObserverCancellable = tabsModel.tabsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.canUpdateCollection else { return }
                self.reloadData()
            }
    }

    private func setupFireModeEmptyState() {
        guard browsingMode == .fire, isFireModeEnabled else { return }
        let emptyStateView = FireModeEmptyStateView(type: .tabSwitcher(onNewFireTab: { [weak self] in
            Pixel.fire(pixel: .fireModeEmptyStateNewTab)
            self?.onNewFireTab?()
        }))
        let hostingController = UIHostingController(rootView: emptyStateView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        fireModeEmptyStateHostingController = hostingController
    }

    func updateEmptyStateVisibility() {
        guard browsingMode == .fire else { return }
        let shouldShowEmptyState = tabsModel.tabs.isEmpty
        fireModeEmptyStateHostingController?.view.isHidden = !shouldShowEmptyState
        collectionView.isHidden = shouldShowEmptyState
    }

    // MARK: - Tracker Count
    
    private func bindTrackerCount() {
        trackerCountCancellable = trackerCountViewModel?.$state
            .sink { [weak self] state in
                self?.applyTrackerCountState(state)
            }
    }

    private func applyTrackerCountState(_ state: TabSwitcherTrackerCountViewModel.State) {
        guard state != lastAppliedTrackerCountState else { return }
        lastAppliedTrackerCountState = state

        guard state.isVisible else {
            trackerInfoModel = nil
            updateTrackerInfoHeaderIfVisible()
            collectionView.collectionViewLayout.invalidateLayout()
            return
        }

        trackerInfoModel = .trackerInfoPanel(
            state: state,
            onTap: { },
            onInfo: { [weak self] in
                self?.presentHideTrackerCountAlert()
            }
        )
        updateTrackerInfoHeaderIfVisible()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func updateTrackerInfoHeaderIfVisible() {
        let indexPath = IndexPath(item: 0, section: 0)
        guard let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
        ) as? TabSwitcherTrackerInfoHeaderView else {
            return
        }
        header.configure(in: self, model: trackerInfoModel)
    }

    private func presentHideTrackerCountAlert() {
        let alert = UIAlertController(title: UserText.tabSwitcherTrackerCountHideTitle,
                                      message: UserText.tabSwitcherTrackerCountHideMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: UserText.tabSwitcherTrackerCountKeepAction, style: .cancel))
        alert.addAction(UIAlertAction(title: UserText.tabSwitcherTrackerCountHideAction, style: .default) { [weak self] _ in
            Pixel.fire(pixel: .tabSwitcherTrackerCountHidden)
            self?.trackerCountViewModel?.hide()
        })
        present(alert, animated: true)
    }

    // MARK: - Public API
    
    var selectedTab: Tab? {
        return tabsModel.get(tabAt: currentSelection)
    }

    func reloadData() {
        if isSearchActive {
            rebuildFilteredTabs()
        }
        collectionView.reloadData()
        updateEmptyStateVisibility()
    }

    // MARK: - Search

    /// Enters search mode showing all tabs of this page (empty query matches everything).
    func beginSearch() {
        isSearchActive = true
        searchQuery = ""
        // 🟣 redundant comment - remove later
        // Allow a vertical drag even when the (few) results fit the frame, so the drag registers
        // and `scrollViewWillBeginDragging` fires — that's what dismisses the keyboard.
        collectionView.alwaysBounceVertical = true
        rebuildFilteredTabs()
        collectionView.reloadData()
    }

    /// Updates the active query and re-filters the displayed tabs.
    func updateSearch(query: String) {
        guard isSearchActive else { return }
        searchQuery = query
        rebuildFilteredTabs()
        collectionView.reloadData()
    }

    /// Leaves search mode and restores the full, model-backed list.
    func endSearch() {
        isSearchActive = false
        searchQuery = ""
        filteredTabs = []
        collectionView.alwaysBounceVertical = false
        collectionView.reloadData()
    }

    private func rebuildFilteredTabs() {
        filteredTabs = TabsSearch.filter(tabsModel.tabs, query: searchQuery)
    }

    /// Number of items the collection view should display, honoring an active search.
    private var displayedCount: Int {
        isSearchActive ? filteredTabs.count : tabsModel.count
    }

    /// The tab shown at a given displayed row (filtered while searching, model order otherwise).
    private func displayedTab(at row: Int) -> Tab? {
        if isSearchActive {
            return filteredTabs.indices.contains(row) ? filteredTabs[row] : nil
        }
        return tabsModel.get(tabAt: row)
    }

    /// The displayed row for a tab, used to refresh the right cell when a tab changes.
    private func displayedIndex(of tab: Tab) -> Int? {
        if isSearchActive {
            return filteredTabs.firstIndex { $0 === tab }
        }
        return tabsModel.indexOf(tab: tab)
    }

    func refreshCurrentTabIndicators() {
        guard currentSelection != nil else { return }
        for cell in collectionView.visibleCells {
            guard let tabCell = cell as? TabViewCell,
                  let tab = tabCell.tab else { continue }
            tabCell.isCurrent = isCurrent(tab: tab)
            tabCell.updateCurrentTabBorder()
        }
    }
    
    func scrollToInitialTab() {
        guard let index = tabsModel.currentIndex,
              index < collectionView.numberOfItems(inSection: 0) else { return }
        collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .bottom, animated: false)
    }

    func enterEditingMode() {
        collectionView.reloadData()
    }

    func exitEditingMode(reloadData: Bool) {
        if reloadData {
            collectionView.reloadData()
        }
    }

    func selectAll() {
        for row in 0..<tabsModel.count {
            collectionView.selectItem(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: [])
        }
    }

    func deselectAll() {
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: false)
        }
    }

    func deleteTabsAtIndexPaths(_ indexPaths: [IndexPath]) {
        guard let pageDelegate else { return }
        let allTabsDeleted = tabsModel.count == indexPaths.count
        let tabsToClose = indexPaths.compactMap { tabsModel.get(tabAt: $0.row) }

        collectionView.performBatchUpdates {
            pageDelegate.isProcessingUpdates = true
            pageDelegate.page(self, willDeleteTabs: tabsToClose, allDeleted: allTabsDeleted)
            collectionView.deleteItems(at: indexPaths)
            currentSelection = tabsModel.currentIndex
            refreshCurrentTabIndicators()
        } completion: { _ in
            pageDelegate.isProcessingUpdates = false
            pageDelegate.pageDidDeleteTabs(self, allDeleted: allTabsDeleted)
        }
    }
    /// Closes a single tab while searching, using the same animated batch-update pattern as
    /// `deleteTabsAtIndexPaths` (and `performDropWith`).
    ///
    /// The safety invariant differs only in *which* index space stays consistent: instead of
    /// "collection index == model index", here it's "collection index == `filteredTabs` index".
    /// We uphold it by mutating `filteredTabs` and calling `deleteItems(at:)` on the same filtered
    /// index inside one `performBatchUpdates`, so the post-update item count matches exactly. The
    /// model is still mutated *by object* via `bulkRemoveTabs` (index-agnostic); the filter array
    /// is never written back to storage — it stays a derived view.
    private func deleteSearchResult(at displayedRow: Int) {
        guard let pageDelegate, filteredTabs.indices.contains(displayedRow) else { return }
        let tab = filteredTabs[displayedRow]
        let wasLastTab = tabsModel.count == 1

        collectionView.performBatchUpdates {
            pageDelegate.isProcessingUpdates = true
            pageDelegate.page(self, willDeleteTabs: [tab], allDeleted: wasLastTab)
            filteredTabs.remove(at: displayedRow)
            collectionView.deleteItems(at: [IndexPath(row: displayedRow, section: 0)])
            currentSelection = tabsModel.currentIndex
            refreshCurrentTabIndicators()
        } completion: { [weak self] _ in
            guard let self else { return }
            pageDelegate.isProcessingUpdates = false
            pageDelegate.pageDidDeleteTabs(self, allDeleted: wasLastTab)
        }
    }

    /// Closes every tab except `retainedTab` while searching ("Close Other Tabs").
    ///
    /// The removed set spans tabs that aren't in the filtered collection (results *and* non-results),
    /// so this can't use animated index-based batch updates. The model is mutated by object via
    /// `bulkRemoveTabs`, then `reloadData()` rebuilds the filtered view. One tab is always retained,
    /// so the model is never emptied (`allDeleted: false`).
    func closeOtherSearchTabs(retaining retainedTab: Tab) {
        guard let pageDelegate else { return }
        let tabsToClose = tabsModel.tabs.filter { $0 !== retainedTab }
        guard !tabsToClose.isEmpty else { return }

        pageDelegate.isProcessingUpdates = true
        pageDelegate.page(self, willDeleteTabs: tabsToClose, allDeleted: false)
        reloadData()
        currentSelection = tabsModel.currentIndex
        pageDelegate.isProcessingUpdates = false
        pageDelegate.pageDidDeleteTabs(self, allDeleted: false)
    }

    // MARK: - Private

    @objc private func handleBackgroundTap(gesture: UITapGestureRecognizer) {
        guard gesture.tappedInWhitespaceAtEndOfCollectionView(collectionView) else { return }
        pageDelegate?.pageDidRequestDismiss(self)
    }

    /// Resolves the rich-card grid item for `tab`, or `nil` for non-AI tabs and
    /// when no provider is wired in (release builds without an explicit injection).
    /// `nil` keeps the cell on the existing screenshot path.
    private func duckAIGridItem(for tab: Tab) -> DuckAIGridItem? {
        guard tab.isAITab else { return nil }
        return duckAIGridContentProvider?.gridItem(for: tab)
    }
}

// MARK: - UICollectionViewDataSource

extension TabSwitcherPageViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayedCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cellIdentifier = tabSwitcherSettings.isGridViewEnabled ? TabViewGridCell.reuseIdentifier : TabViewListCell.reuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TabViewCell else {
            fatalError("Failed to dequeue cell \(cellIdentifier) as TabViewCell")
        }
        cell.delegate = self
        cell.isDeleting = false

        if let tab = displayedTab(at: indexPath.row) {
            tab.removeObserver(self)
            tab.addObserver(self)
            cell.update(withTab: tab,
                        isSelectionModeEnabled: pageDelegate?.isEditing ?? false,
                        preview: previewsSource?.preview(for: tab),
                        isFireModeEnabled: isFireModeEnabled,
                        duckAIGridItem: duckAIGridItem(for: tab),
                        thumbnailLoader: duckAIGridContentProvider)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: TabSwitcherTrackerInfoHeaderView.reuseIdentifier,
            for: indexPath
        ) as? TabSwitcherTrackerInfoHeaderView else {
            return UICollectionReusableView()
        }

        header.configure(in: self, model: trackerInfoModel)
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension TabSwitcherPageViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if pageDelegate?.isEditing == true {
            Pixel.fire(pixel: .tabSwitcherTabSelected)
            (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
            pageDelegate?.page(self, didSelectTabAt: indexPath.row)
        } else {
            // While searching the tapped row is a filtered index — resolve the tab and map
            // it back to its real position so `selectedTab` (model-indexed) stays correct.
            let tab = displayedTab(at: indexPath.row)
            currentSelection = tab.flatMap { tabsModel.indexOf(tab: $0) } ?? indexPath.row
            Pixel.fire(pixel: .tabSwitcherSwitchTabs, withAdditionalParameters: [
                PixelParameters.browsingMode: browsingMode.pixelParamValue
            ])
            if let tab {
                if tab.isAITab {
                    DailyPixel.fireDailyAndCount(pixel: .tabManagerSwitchToAITab)
                } else {
                    DailyPixel.fireDailyAndCount(pixel: .tabManagerSwitchToWebTab)
                }
            }
            pageDelegate?.pageDidRequestDismiss(self)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? TabViewCell)?.refreshSelectionAppearance()
        pageDelegate?.page(self, didDeselectTab: ())
        Pixel.fire(pixel: .tabSwitcherTabDeselected)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 🟣 redundant comment - remove later
        // The user started scrolling the results list — dismiss the keyboard.
        // Only relevant while searching; ignored for normal browsing scrolls.
        guard isSearchActive else { return }
        pageDelegate?.pageDidScrollSearchResults(self)
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return !(pageDelegate?.isEditing ?? false) && !isSearchActive
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !indexPaths.isEmpty else { return nil }

        // While searching the collection shows a filtered view, so the default index-based menu
        // would resolve the wrong tabs. Resolve the long-pressed tab by object up-front; the menu
        // is then built by object (search) or by index (normal). Config creation and pixels are
        // shared — only the menu source differs.
        var searchTab: Tab?
        // 🚩feature flag entry point?
        if isSearchActive {
            guard let row = indexPaths.first?.row, let tab = displayedTab(at: row) else { return nil }
            searchTab = tab
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let modeParam = [PixelParameters.browsingMode: self.browsingMode.pixelParamValue]
            Pixel.fire(pixel: .tabSwitcherLongPress, withAdditionalParameters: modeParam)
            DailyPixel.fire(pixel: .tabSwitcherLongPressDaily, withAdditionalParameters: modeParam)
            if let searchTab {
                return self.pageDelegate?.page(self, searchContextMenuForTab: searchTab)
            }
            return self.pageDelegate?.page(self, contextMenuForTabsAt: indexPaths)
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension TabSwitcherPageViewController: UICollectionViewDelegateFlowLayout {

    private func calculateColumnWidth(minimumColumnWidth: CGFloat, maxColumns: Int) -> CGFloat {
        let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        let spacing = layout?.sectionInset.left ?? 0.0
        let contentWidth = collectionView.bounds.width - spacing
        let numberOfColumns = min(maxColumns, Int(contentWidth / minimumColumnWidth))
        return contentWidth / CGFloat(numberOfColumns) - spacing
    }

    private func calculateRowHeight(columnWidth: CGFloat) -> CGFloat {
        let contentAspectRatio = collectionView.bounds.width / collectionView.bounds.height
        let heightToFit = (columnWidth / contentAspectRatio) + TabViewCell.Constants.cellHeaderHeight
        let preferredMaxHeight = collectionView.bounds.height / TabSwitcherViewController.Constants.preferredMinNumberOfRows
        let preferredHeight = min(preferredMaxHeight, heightToFit)
        return min(TabSwitcherViewController.Constants.cellMaxHeight,
                   max(TabSwitcherViewController.Constants.cellMinHeight, preferredHeight))
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if tabSwitcherSettings.isGridViewEnabled {
            let columnWidth = calculateColumnWidth(minimumColumnWidth: 150, maxColumns: 4)
            let rowHeight = calculateRowHeight(columnWidth: columnWidth)
            return CGSize(width: floor(columnWidth), height: floor(rowHeight))
        } else {
            let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
            let spacing = layout?.sectionInset.left ?? 0.0
            let width = min(664, collectionView.bounds.size.width - 2 * spacing)
            return CGSize(width: width, height: 70)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard trackerInfoModel != nil else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: TabSwitcherTrackerInfoHeaderView.estimatedHeight)
    }
}

// MARK: - TabViewCellDelegate

extension TabSwitcherPageViewController: TabViewCellDelegate {

    func deleteTab(tab: Tab) {
        if isSearchActive {
            // Collection shows the filtered view, so delete on the *filtered* index and keep
            // `filteredTabs` + the collection in lockstep (see deleteSearchResult).
            guard let displayedRow = filteredTabs.firstIndex(where: { $0 === tab }) else { return }
            deleteSearchResult(at: displayedRow)
        } else {
            guard let index = tabsModel.indexOf(tab: tab) else { return }
            deleteTabsAtIndexPaths([IndexPath(row: index, section: 0)])
        }
    }

    func isCurrent(tab: Tab) -> Bool {
        return currentSelection == tabsModel.indexOf(tab: tab)
    }

    func tabViewCellDidBeginSwipe(_ cell: TabViewCell) {
        pageDelegate?.pageCellDidBeginSwipe(self)
    }

    func tabViewCellDidEndSwipe(_ cell: TabViewCell) {
        pageDelegate?.pageCellDidEndSwipe(self)
    }
}

// MARK: - TabObserver

extension TabSwitcherPageViewController: TabObserver {

    func didChange(tab: Tab) {
        guard let index = displayedIndex(of: tab),
              let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? TabViewCell else {
            return
        }
        guard cell.tab?.uid == tab.uid else {
            DailyPixel.fireDaily(.debugTabSwitcherDidChangeInvalidState)
            return
        }
        cell.update(withTab: tab,
                    isSelectionModeEnabled: pageDelegate?.isEditing ?? false,
                    preview: previewsSource?.preview(for: tab),
                    isFireModeEnabled: isFireModeEnabled,
                    duckAIGridItem: duckAIGridItem(for: tab),
                    thumbnailLoader: duckAIGridContentProvider)
    }
}

// MARK: - UICollectionViewDragDelegate

extension TabSwitcherPageViewController: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        return ((pageDelegate?.isEditing ?? false) || isSearchActive) ? [] : [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
        pageDelegate?.pageCellDidBeginDrag(self)
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
        pageDelegate?.pageCellDidEndDrag(self)
    }
}

// MARK: - UICollectionViewDropDelegate

extension TabSwitcherPageViewController: UICollectionViewDropDelegate {

    func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        return .init(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
        guard let destination = coordinator.destinationIndexPath,
              let item = coordinator.items.first,
              let source = item.sourceIndexPath
        else { return }

        collectionView.performBatchUpdates {
            guard let tab = tabsModel.get(tabAt: source.row) else { return }
            tabsModel.move(tab: tab, to: destination.row)
            currentSelection = tabsModel.currentIndex
            collectionView.deleteItems(at: [source])
            collectionView.insertItems(at: [destination])
        } completion: { [weak self] _ in
            guard let self else { return }
            if self.pageDelegate?.isEditing == true {
                self.reloadData()
                collectionView.selectItem(at: destination, animated: true, scrollPosition: [])
            } else {
                collectionView.reloadItems(at: [IndexPath(row: self.currentSelection ?? 0, section: 0)])
            }
            self.pageDelegate?.page(self, didReorderTabs: ())
            coordinator.drop(item.dragItem, toItemAt: destination)
        }
    }
}

// MARK: - UITapGestureRecognizer Helpers

private extension UITapGestureRecognizer {
    
    func tappedInWhitespaceAtEndOfCollectionView(_ collectionView: UICollectionView) -> Bool {
        guard collectionView.indexPathForItem(at: self.location(in: collectionView)) == nil else { return false }
        let location = self.location(in: collectionView)
           
        // Now check if the tap is in the whitespace area at the end
        let lastSection = collectionView.numberOfSections - 1
        let lastItemIndex = collectionView.numberOfItems(inSection: lastSection) - 1
        
        // Get the frame of the last item
        // If there are no items in the last section, the entire area is whitespace
       guard lastItemIndex >= 0 else { return true }
        
        let lastItemIndexPath = IndexPath(item: lastItemIndex, section: lastSection)
        let lastItemFrame = collectionView.layoutAttributesForItem(at: lastItemIndexPath)?.frame ?? .zero
        
        // Check if the tap is below the last item.
        // Add 10px buffer to ensure it's whitespace.
        if location.y > lastItemFrame.maxY + 15 // below the bottom of the last item is definitely the end
            || (location.x > lastItemFrame.maxX + 15 && location.y > lastItemFrame.minY) { // to the right of the last item is the end as long as it's also at least below the start of the frame
            // The tap is in the whitespace area at the end
        return true
    }
    
        return false
    }
}

// MARK: - TabsSearch

/// Stateless, non-mutating search over a snapshot of open tabs.
///
/// Filtering happens entirely on a derived copy of the tabs array — the source
/// `TabsModel` is never modified. Matching is performed against the website title
/// and URL carried by `Tab.link`, using Foundation's locale-aware, case- and
/// diacritic-insensitive comparison (`localizedStandardContains`).
enum TabsSearch {
    // 🟣 redundant comment - remove later
    // PoC copy, intentionally not localized: keeps the prototype self-contained and avoids the
    // build-time string-extraction step. For production these should become localized `UserText`.
    static let buttonTitle = "Search"
    static let placeholder = "Search open tabs"

    /// Returns the subset of `tabs` whose website title or URL matches `query`.
    ///
    /// - An empty or whitespace-only query returns all tabs unchanged.
    /// - Tabs without a `link` (e.g. the home/NTP tab) have no searchable content and are excluded from non-empty queries.
    static func filter(_ tabs: [Tab], query: String) -> [Tab] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tabs }

        return tabs.filter { tab in
            guard let link = tab.link else { return false }

            if link.displayTitle.localizedStandardContains(trimmedQuery) {
                return true
            }
            if let title = link.title, title.localizedStandardContains(trimmedQuery) {
                return true
            }
            return link.url.absoluteString.localizedStandardContains(trimmedQuery)
        }
    }
}
