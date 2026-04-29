//
//  BookmarksBarMenuPopover.swift
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

import AppKit
import Foundation

protocol BookmarksBarMenuPopoverDelegate: AnyObject {
    func popoverShouldClose(_ popover: BookmarksBarMenuPopover) -> Bool
    func popoverDidClose(_ popover: BookmarksBarMenuPopover)
    func openNextBookmarksMenu(_ sender: BookmarksBarMenuPopover)
    func openPreviousBookmarksMenu(_ sender: BookmarksBarMenuPopover)
}

extension BookmarksBarMenuPopoverDelegate {
    func popoverShouldClose(_ popover: BookmarksBarMenuPopover) -> Bool { true }
    func popoverDidClose(_ popover: BookmarksBarMenuPopover) {}
}

/// A custom-windowed replacement for `NSPopover` used by the bookmarks bar menu.
/// Mirrors the slice of the `NSPopover` API the rest of the codebase relies on
/// (`isShown`, `positioningView`, `preferredContentSize`, `delegate`, the various
/// `show(...)` variants, `close()`) and keeps the responder-chain trick that the
/// view controller uses to find its enclosing popover via `nextResponder as? Self`.
final class BookmarksBarMenuPopover: NSResponder {

    /// Mirrors the `NSPopover.Behavior` cases the bookmarks code toggles. Currently
    /// vestigial — auto-close is handled inside `BookmarksBarMenuViewController`.
    enum Behavior {
        case transient
        case applicationDefined
    }

    static let popoverInsets = NSEdgeInsets(top: 13, left: 13, bottom: 13, right: 13)

    private let bookmarkManager: BookmarkManager
    private let dragDropManager: BookmarkDragDropManager
    private(set) var rootFolder: BookmarkFolder?

    weak var delegate: BookmarksBarMenuPopoverDelegate?
    var behavior: Behavior = .transient

    private(set) var window: BookmarksBarMenuWindow?
    private(set) var preferredEdge: NSRectEdge?
    private(set) weak var positioningView: NSView?
    private(set) var contentViewController: NSViewController?
    private var positioningRect: NSRect = .zero

    /// Temporary view inserted into table-view positioning to keep the popover anchored
    /// while the table reloads. Removed in `close()`.
    private weak var temporaryPositioningHost: NSView?

    var viewController: BookmarksBarMenuViewController {
        // swiftlint:disable:next force_cast
        contentViewController as! BookmarksBarMenuViewController
    }

    var isShown: Bool { window?.isVisible == true }

    var mainWindow: NSWindow? { window?.parent }

    init(bookmarkManager: BookmarkManager, dragDropManager: BookmarkDragDropManager, rootFolder: BookmarkFolder? = nil) {
        self.bookmarkManager = bookmarkManager
        self.dragDropManager = dragDropManager
        self.rootFolder = rootFolder

        super.init()

        let controller = BookmarksBarMenuViewController(bookmarkManager: bookmarkManager, dragDropManager: dragDropManager, rootFolder: rootFolder)
        controller.delegate = self
        contentViewController = controller
    }

    required init?(coder: NSCoder) {
        fatalError("BookmarksBarMenuPopover: Bad initializer")
    }

    deinit {
#if DEBUG
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    func reloadData(withRootFolder rootFolder: BookmarkFolder) {
        self.rootFolder = rootFolder
        viewController.reloadData(withRootFolder: rootFolder)
    }

    // MARK: - Show

    func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        Self.closeBookmarkListPopovers(shownIn: positioningView.window, except: self)

        var positioningView = positioningView
        var positioningRect = positioningRect
        // add temporary view to bookmarks menu table to prevent popover jumping on table reloading
        // showing the popover against coordinates in the table view breaks popover positioning
        // the view will be removed in `close()`
        if positioningView is NSTableCellView,
           let tableView = positioningView.superview?.superview as? NSTableView {
            let v = NSView(frame: positioningView.convert(positioningRect, to: tableView))
            positioningRect = v.bounds
            positioningView = v
            tableView.addSubview(v)
            temporaryPositioningHost = v
        }

        guard let parentWindow = positioningView.window else {
            assertionFailure("BookmarksBarMenuPopover: positioning view has no window")
            return
        }

        self.positioningView = positioningView
        self.positioningRect = positioningRect
        self.preferredEdge = preferredEdge

        viewController.adjustPreferredContentSize(positionedRelativeTo: positioningRect, of: positioningView, at: preferredEdge)

        let window = ensureWindow()

        // Wire the responder chain so `vc.nextResponder is BookmarksBarMenuPopover` keeps working.
        if window.contentViewController !== contentViewController {
            window.contentViewController = contentViewController
            contentViewController?.nextResponder = self
            self.nextResponder = window
        }

        let frame = computeFrame(contentSize: viewController.preferredContentSize, in: parentWindow)
        window.setFrame(frame, display: false)

        if window.parent !== parentWindow {
            window.parent?.removeChildWindow(window)
            parentWindow.addChildWindow(window, ordered: .above)
        }
        window.orderFront(nil)
        window.makeKey()
    }

    /// Shows the popover below the specified rect inside the view bounds with the popover's pin positioned in the middle of the rect
    func show(positionedBelow positioningRect: NSRect, in positioningView: NSView) {
        assert(!positioningView.isHidden && positioningView.alphaValue > 0)

        let positioningRect = NSRect(x: positioningRect.midX - 1, y: positioningRect.origin.y, width: 2, height: positioningRect.height)
        let preferredEdge: NSRectEdge = positioningView.isFlipped ? .maxY : .minY
        show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
    }

    /// Shows the popover below the specified view with the popover's pin positioned in the middle of the view
    func show(positionedBelow view: NSView) {
        show(positionedBelow: view.bounds, in: view)
    }

    func show(positionedAsSubmenuAgainst positioningView: NSView) {
        assert(!positioningView.isHidden && positioningView.alphaValue > 0)
        let positioningRect = NSRect(x: 0, y: positioningView.bounds.midY - 1, width: positioningView.bounds.width, height: 2)
        show(relativeTo: positioningRect, of: positioningView, preferredEdge: .maxX)
    }

    private func ensureWindow() -> BookmarksBarMenuWindow {
        if let window { return window }
        let window = BookmarksBarMenuWindow()
        self.window = window
        return window
    }

    /// Computes the on-screen frame for the popover. Replicates the frame adjustment
    /// the previous `NSPopover` subclass performed in its overridden `adjustFrame(_:)`,
    /// minus the NSPopover-supplied initial position (we compute that ourselves here).
    private func computeFrame(contentSize: NSSize, in parentWindow: NSWindow) -> NSRect {
        guard let positioningView, let preferredEdge,
              let screenFrame = parentWindow.screen?.visibleFrame else {
            return NSRect(origin: .zero, size: contentSize)
        }

        let offset = viewController.preferredContentOffset
        let originY = (positioningView.isFlipped ? positioningView.bounds.minY : positioningView.bounds.maxY) + offset.y
        let windowPoint = positioningView.convert(NSPoint(x: offset.x, y: originY), to: nil)
        let screenPoint = parentWindow.convertPoint(toScreen: windowPoint)

        var frame = NSRect(origin: .zero, size: contentSize)

        // The previous NSPopover-based positioning was tuned for a window with chrome
        // around the visible content. Our custom window has no chrome, so we add back
        // the chrome inset (popoverInsets) on the leading and top edges so the visible
        // content lands where it used to.
        if case .maxX = preferredEdge {
            // submenu — visible content's left edge sits insets.left to the right of the
            // parent row's right edge; vertical anchor matches the original `+36` offset
            // minus the chrome top inset.
            let positioningRectInWindow = positioningView.convert(positioningRect, to: nil)
            let positioningRectInScreen = parentWindow.convertToScreen(positioningRectInWindow)
            frame.origin.x = min(max(screenFrame.minX, positioningRectInScreen.maxX + Self.popoverInsets.left), screenFrame.maxX - frame.width)
            frame.origin.y = min(max(screenFrame.minY, screenPoint.y - frame.size.height + 36 - Self.popoverInsets.top), screenFrame.maxY)
        } else {
            // context menu — visible content top-left aligned with bottom-left of the
            // positioning view (with the same vertical chrome compensation).
            frame.origin.x = min(max(screenFrame.minX, screenPoint.x), screenFrame.maxX - frame.width)
            frame.origin.y = min(max(screenFrame.minY, screenPoint.y - frame.size.height - 2 * Self.popoverInsets.top), screenFrame.maxY)
        }

        return frame
    }

    /// Recompute and apply the window frame after the view controller's
    /// `preferredContentSize` or `preferredContentOffset` changes (e.g. on
    /// live bookmarks list updates or scroll-driven menu growth).
    func updateWindowFrame() {
        guard let window, window.isVisible, let parentWindow = window.parent else { return }
        let frame = computeFrame(contentSize: viewController.preferredContentSize, in: parentWindow)
        window.setFrame(frame, display: true)
    }

    // MARK: - Close

    func close() {
        guard let window, window.isVisible else { return }
        if delegate?.popoverShouldClose(self) == false { return }

        // Close descendant menu popovers first. NSPopover cascaded this via its window
        // hierarchy; our NSPanel-backed children would otherwise remain on screen.
        let childPopovers = (window.childWindows ?? []).compactMap {
            $0.contentViewController?.nextResponder as? BookmarksBarMenuPopover
        }
        for childPopover in childPopovers {
            childPopover.close()
        }

        if let temporaryPositioningHost {
            temporaryPositioningHost.removeFromSuperview()
            self.temporaryPositioningHost = nil
        }

        window.parent?.removeChildWindow(window)
        window.orderOut(nil)

        // Mirror NSPopover's notification so existing observers (e.g. BookmarksOutlineView
        // updating its highlight state) keep working without being aware of the rewrite.
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: self)
        delegate?.popoverDidClose(self)
    }

    // MARK: - Static

    /// close other `BookmarksBarMenuPopover`-s shown from the main window when opening a new one
    static func closeBookmarkListPopovers(shownIn window: NSWindow?, except popoverToKeep: BookmarksBarMenuPopover? = nil) {
        guard let window,
              // ignore when opening a submenu from another popover
              !(window.contentViewController?.nextResponder is Self) else { return }
        for case let .some(popover as BookmarksBarMenuPopover) in (window.childWindows ?? []).map(\.contentViewController?.nextResponder)
        where popover !== popoverToKeep && popover.isShown {
            popover.close()
        }
    }
}

extension BookmarksBarMenuPopover: BookmarksBarMenuViewControllerDelegate {

    func closeBookmarksPopovers(_ sender: BookmarksBarMenuViewController) {
        var window: NSWindow? = sender.view.window
        // find root popover in bookmarks menu hierarchy
        while let parent = window?.parent, parent.contentViewController?.nextResponder is Self {
            window = parent
        }
        guard let popover = window?.contentViewController?.nextResponder as? Self else {
            assertionFailure("Expected BookmarksBarMenuPopover as \(window?.debugDescription ?? "<nil>")‘s contentViewController nextResponder")
            return
        }
        popover.close()
    }

    func popover(shouldPreventClosure: Bool) {
        var window: NSWindow? = contentViewController?.view.window
        while let popover = window?.contentViewController?.nextResponder as? Self {
            popover.behavior = shouldPreventClosure ? .applicationDefined : .transient
            window = window?.parent
        }
    }

    func openNextBookmarksMenu(_ sender: BookmarksBarMenuViewController) {
        delegate?.openNextBookmarksMenu(self)
    }

    func openPreviousBookmarksMenu(_ sender: BookmarksBarMenuViewController) {
        delegate?.openPreviousBookmarksMenu(self)
    }

}
