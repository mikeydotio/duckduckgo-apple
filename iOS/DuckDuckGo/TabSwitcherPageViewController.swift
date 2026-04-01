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
    func page(_ page: TabSwitcherPageViewController, willDeleteTabs tabs: [Tab])
    func page(_ page: TabSwitcherPageViewController, didDeleteAllTabs: Bool)
    func page(_ page: TabSwitcherPageViewController, didReorderTabs: Void)
    func page(_ page: TabSwitcherPageViewController, contextMenuForTabsAt indexPaths: [IndexPath]) -> UIMenu?
    func pageDidRequestDismiss(_ page: TabSwitcherPageViewController)

    var isEditing: Bool { get }
    var currentSelection: Int? { get set }
    var isProcessingUpdates: Bool { get set }
    var canDismissOnEmpty: Bool { get }
}

class TabSwitcherPageViewController: UIViewController {

    private(set) var collectionView: UICollectionView!

    let browsingMode: BrowsingMode
    let tabsModel: TabsModelManaging
    weak var previewsSource: TabPreviewsSource?
    let tabSwitcherSettings: TabSwitcherSettings
    var isFireModeEnabled: Bool
    weak var pageDelegate: TabSwitcherPageDelegate?

    var selectedIndexPaths: [IndexPath] {
        collectionView.indexPathsForSelectedItems ?? []
    }

    init(browsingMode: BrowsingMode,
         tabsModel: TabsModelManaging,
         previewsSource: TabPreviewsSource,
         tabSwitcherSettings: TabSwitcherSettings,
         isFireModeEnabled: Bool) {
        self.browsingMode = browsingMode
        self.tabsModel = tabsModel
        self.previewsSource = previewsSource
        self.tabSwitcherSettings = tabSwitcherSettings
        self.isFireModeEnabled = isFireModeEnabled
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
    }

    // MARK: - Public API

    func reloadData() {
        collectionView.reloadData()
    }

    func scrollToTab(at index: Int) {
        guard index < collectionView.numberOfItems(inSection: 0) else { return }
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
        pageDelegate.page(self, willDeleteTabs: tabsToClose)

        collectionView.performBatchUpdates {
            pageDelegate.isProcessingUpdates = true
            tabsToClose.forEach { tabsModel.remove(tab: $0) }
            collectionView.deleteItems(at: indexPaths)
            if allTabsDeleted && !pageDelegate.canDismissOnEmpty && pageDelegate.isEditing {
                exitEditingMode(reloadData: false)
            }
        } completion: { _ in
            pageDelegate.isProcessingUpdates = false
            pageDelegate.page(self, didDeleteAllTabs: allTabsDeleted)
        }
    }

    // MARK: - Private

    @objc private func handleBackgroundTap(gesture: UITapGestureRecognizer) {
        guard gesture.tappedInWhitespaceAtEndOfCollectionView(collectionView) else { return }
        if pageDelegate?.isEditing == true {
            exitEditingMode(reloadData: true)
            pageDelegate?.page(self, didDeselectTab: ())
        } else {
            pageDelegate?.pageDidRequestDismiss(self)
        }
    }
}

// MARK: - UICollectionViewDataSource

extension TabSwitcherPageViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabsModel.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cellIdentifier = tabSwitcherSettings.isGridViewEnabled ? TabViewGridCell.reuseIdentifier : TabViewListCell.reuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath) as? TabViewCell else {
            fatalError("Failed to dequeue cell \(cellIdentifier) as TabViewCell")
        }
        cell.delegate = self
        cell.isDeleting = false

        if indexPath.row < tabsModel.count,
           let tab = tabsModel.get(tabAt: indexPath.row) {
            tab.removeObserver(self)
            tab.addObserver(self)
            cell.update(withTab: tab,
                        isSelectionModeEnabled: pageDelegate?.isEditing ?? false,
                        preview: previewsSource?.preview(for: tab),
                        isFireModeEnabled: isFireModeEnabled)
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

        // Header configuration is handled by the parent via updateTrackerHeader
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
            pageDelegate?.currentSelection = indexPath.row
            Pixel.fire(pixel: .tabSwitcherSwitchTabs)
            if let tab = tabsModel.get(tabAt: indexPath.row) {
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

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return !(pageDelegate?.isEditing ?? false)
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard !indexPaths.isEmpty else { return nil }

        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            Pixel.fire(pixel: .tabSwitcherLongPress)
            DailyPixel.fire(pixel: .tabSwitcherLongPressDaily)
            return self.pageDelegate?.page(self, contextMenuForTabsAt: indexPaths)
        }
        return configuration
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
        // Header size is controlled by parent via trackerInfoModel; default to zero
        return .zero
    }
}

// MARK: - TabViewCellDelegate

extension TabSwitcherPageViewController: TabViewCellDelegate {

    func deleteTab(tab: Tab) {
        guard let index = tabsModel.indexOf(tab: tab) else { return }
        deleteTabsAtIndexPaths([IndexPath(row: index, section: 0)])
    }

    func isCurrent(tab: Tab) -> Bool {
        return pageDelegate?.currentSelection == tabsModel.indexOf(tab: tab)
    }
}

// MARK: - TabObserver

extension TabSwitcherPageViewController: TabObserver {

    func didChange(tab: Tab) {
        guard let index = tabsModel.indexOf(tab: tab),
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
                    isFireModeEnabled: isFireModeEnabled)
    }
}

// MARK: - UICollectionViewDragDelegate

extension TabSwitcherPageViewController: UICollectionViewDragDelegate {

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        return (pageDelegate?.isEditing ?? false) ? [] : [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        return [UIDragItem(itemProvider: NSItemProvider())]
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
            pageDelegate?.currentSelection = tabsModel.currentIndex
            collectionView.deleteItems(at: [source])
            collectionView.insertItems(at: [destination])
        } completion: { [weak self] _ in
            guard let self else { return }
            if self.pageDelegate?.isEditing == true {
                self.reloadData()
                collectionView.selectItem(at: destination, animated: true, scrollPosition: [])
            } else {
                collectionView.reloadItems(at: [IndexPath(row: self.pageDelegate?.currentSelection ?? 0, section: 0)])
            }
            self.pageDelegate?.page(self, didReorderTabs: ())
            coordinator.drop(item.dragItem, toItemAt: destination)
        }
    }
}
