//
//  TabsBarViewControllerSizingTests.swift
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

import XCTest
import UIKit

@testable import DuckDuckGo

final class TabsBarViewControllerSizingTests: XCTestCase {

    private let accuracy: CGFloat = 0.001
    private let minWidth = TabsBarViewController.Constants.minItemWidth

    private func itemWidth(_ available: CGFloat, _ visibleItems: Int, maxWidth: CGFloat) -> CGFloat {
        TabsBarViewController.itemWidth(availableWidth: available, visibleItems: visibleItems, minWidth: minWidth, maxWidth: maxWidth)
    }

    func testTabsAreCappedAtMaxWidth() {
        XCTAssertEqual(itemWidth(900, 1, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 2, maxWidth: 300), 300, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 3, maxWidth: 300), 300, accuracy: accuracy)
    }

    func testTabsFillEquallyWhenMaxWidthDoesNotBind() {
        XCTAssertEqual(itemWidth(900, 4, maxWidth: 300), 225, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 6, maxWidth: 300), 150, accuracy: accuracy)
    }

    func testTabsFloorAtMinWidth() {
        XCTAssertEqual(itemWidth(900, 8, maxWidth: 300), 120, accuracy: accuracy)
        XCTAssertEqual(itemWidth(900, 20, maxWidth: 300), 120, accuracy: accuracy)
    }

    func testMinWidthWinsWhenMaxBelowFloor() {
        XCTAssertEqual(itemWidth(300, 1, maxWidth: 99), 120, accuracy: accuracy)
    }

    func testZeroVisibleItemsReturnsZero() {
        XCTAssertEqual(itemWidth(900, 0, maxWidth: 300), 0, accuracy: accuracy)
    }

    // MARK: - maxItemWidth(stripWidth:windowWidth:windowHeight:screenLongEdge:)

    func testWhenWindowIsPortraitShapedThenReturnsHalfRegardlessOfScreenSize() {
        // A narrow Slide Over pane is portrait-shaped even on a landscape-held iPad; the physical
        // screen size must not leak into the result via a device/scene-orientation check.
        let smallScreen = TabsBarViewController.maxItemWidth(stripWidth: 280, windowWidth: 320, windowHeight: 400, screenLongEdge: 50)
        let largeScreen = TabsBarViewController.maxItemWidth(stripWidth: 280, windowWidth: 320, windowHeight: 400, screenLongEdge: 5000)
        XCTAssertEqual(smallScreen, 140, accuracy: accuracy)
        XCTAssertEqual(largeScreen, 140, accuracy: accuracy)
    }

    func testWhenWindowIsSquareThenReturnsHalf() {
        XCTAssertEqual(
            TabsBarViewController.maxItemWidth(stripWidth: 400, windowWidth: 500, windowHeight: 500, screenLongEdge: 1194),
            200,
            accuracy: accuracy
        )
    }

    func testWhenWindowIsLandscapeShapedAndScreenCapBindsThenReturnsScreenCappedValue() {
        // Full-screen iPad landscape: chrome = windowWidth - stripWidth = 194.
        XCTAssertEqual(
            TabsBarViewController.maxItemWidth(stripWidth: 1000, windowWidth: 1194, windowHeight: 834, screenLongEdge: 1194),
            330,
            accuracy: accuracy
        )
    }

    func testWhenWindowIsLandscapeShapedAndHalfBindsThenReturnsHalf() {
        // A narrow but landscape-shaped tile: half of the strip is still tighter than a third of
        // the eventual full-screen strip, so half wins.
        XCTAssertEqual(
            TabsBarViewController.maxItemWidth(stripWidth: 200, windowWidth: 400, windowHeight: 300, screenLongEdge: 1194),
            100,
            accuracy: accuracy
        )
    }

    @MainActor
    func testCreateBuildsProgrammaticHierarchy() {
        let controller = TabsBarViewController.create()

        controller.loadViewIfNeeded()

        XCTAssertNotNil(controller.collectionView)
        XCTAssertNotNil(controller.buttonsBackground)
        XCTAssertNotNil(controller.buttonsStack)
        XCTAssertIdentical(controller.collectionView.delegate, controller)
        XCTAssertIdentical(controller.collectionView.dataSource, controller)
        XCTAssertEqual(controller.buttonsStack.spacing, TabsBarViewController.Constants.stackSpacing)
        XCTAssertEqual(controller.buttonsStack.arrangedSubviews.count, 4)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[0], controller.addTabButton)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[1], controller.aiChatChip)
        XCTAssertIdentical(controller.buttonsStack.arrangedSubviews[2], controller.fireButton)
    }

    @MainActor
    func testCollectionViewRegistersTabsBarCell() {
        let controller = TabsBarViewController.create()

        controller.loadViewIfNeeded()

        let cell = controller.collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier,
                                                                 for: IndexPath(item: 0, section: 0))
        XCTAssertTrue(cell is TabsBarCell)
    }
}
