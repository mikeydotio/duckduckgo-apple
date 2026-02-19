//
//  AIChatState.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import AIChat
import Combine

@objc enum AIChatPresentationMode: Int {
    case hidden = 0
    case sidebar = 1
    case floating = 2
}

/// Represents the per-tab AI Chat state, including persisted session data
/// and transient UI lifecycle references (view controller, floating window).

@objc(AIChatSidebar)
final class AIChatState: NSObject {

    // MARK: - Persisted State

    /// The initial AI chat URL to be loaded.
    private let initialAIChatURL: URL

    private let burnerMode: BurnerMode

    /// The AI chat URL that was active in the sidebar.
    private(set) var aiChatURL: URL?

    /// The AI chat restoration data that was active in the sidebar.
    private(set) var restorationData: AIChatRestorationData?

    /// The current presentation mode of the AI Chat for this tab.
    private(set) var presentationMode: AIChatPresentationMode = .hidden

    /// Whether the chat is currently visible (sidebar or floating).
    var isPresented: Bool { presentationMode != .hidden }

    /// Whether the chat is in a floating window.
    var isDetached: Bool { presentationMode == .floating }

    /// The date when the sidebar was last hidden, if applicable.
    private(set) var hiddenAt: Date?

    /// The user-chosen sidebar width for this tab, or `nil` to use the default.
    var sidebarWidth: CGFloat?

    // MARK: - Transient UI Lifecycle

    /// The view controller that displays the AI Chat contents.
    /// Set by `AIChatStateProvider` when the view controller is created.
    var chatViewController: AIChatViewController? {
        didSet {
            subscribeToRestorationDataUpdates()
            chatViewControllerSubject.send(chatViewController)
        }
    }

    /// The floating window controller when the chat is detached from the sidebar.
    /// This is transient (not persisted); use `isDetached` for restoration.
    var floatingWindowController: AIChatFloatingWindowController?

    private let chatViewControllerSubject = CurrentValueSubject<AIChatViewController?, Never>(nil)

    /// Publisher that emits the current view controller's `pageContextRequestedPublisher` and automatically
    /// switches to new view controller's publisher when the view controller changes.
    var pageContextRequestedPublisher: AnyPublisher<Void, Never> {
        chatViewControllerSubject
            .compactMap { $0?.pageContextRequestedPublisher }
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// The current AI chat URL being displayed.
    public var currentAIChatURL: URL {
        get {
            if let chatViewController {
                return chatViewController.currentAIChatURL
            } else {
                return aiChatURL ?? initialAIChatURL
            }
        }
    }

    private let aiChatRemoteSettings = AIChatRemoteSettings()

    /// Creates a sidebar wrapper with the specified initial AI chat URL.
    /// - Parameter initialAIChatURL: The initial AI chat URL to load. If nil, defaults to the URL from AIChatRemoteSettings.
    init(initialAIChatURL: URL? = nil, burnerMode: BurnerMode) {
        self.initialAIChatURL = initialAIChatURL ?? aiChatRemoteSettings.aiChatURL.forAIChatSidebar()
        self.burnerMode = burnerMode
    }

    /// Marks the chat as visible in the sidebar.
    public func setRevealed() {
        presentationMode = .sidebar
        hiddenAt = nil
    }

    /// Marks the chat as hidden.
    public func setHidden(at date: Date = Date()) {
        presentationMode = .hidden
        if hiddenAt == nil {
            hiddenAt = date
        }
    }

    /// Marks the chat as presented in a floating window.
    public func setDetached() {
        presentationMode = .floating
    }

    /// Marks the chat as docked back into the sidebar and clears the floating controller.
    public func setDocked() {
        presentationMode = .sidebar
        floatingWindowController = nil
    }

    /// Returns true if the sidebar session has expired based on the configured timeout.
    /// A session is expired if the sidebar was hidden and the time since hiding exceeds the timeout.
    public var isSessionExpired: Bool {
        guard let hiddenAt else { return false }
        return hiddenAt.minutesSinceNow() > aiChatRemoteSettings.sessionTimeoutMinutes
    }

    /// Subscribes to restoration data updates from the sidebar view controller.
    /// This method is called automatically when the chatViewController is set.
    private func subscribeToRestorationDataUpdates() {
        cancellables.removeAll()

        chatViewController?.chatRestorationDataPublisher?
            .sink { [weak self] restorationData in
                self?.restorationData = restorationData
            }
            .store(in: &cancellables)
    }

    /// Tears down UI artifacts (floating window, web view) associated with this state.
    /// Must be called from `@MainActor` context before `persistStateAndReset`.
    @MainActor
    public func tearDownUI() {
        floatingWindowController?.close()
        chatViewController?.stopLoading()
        chatViewController?.removeCompletely()
    }

    /// Snapshots the current URL (if persisting), nils transient references, and marks the state as hidden.
    /// Call `tearDownUI()` from the presenter before this when UI artifacts exist.
    public func persistStateAndReset(persistingState: Bool) {
        if persistingState, let chatViewController {
            aiChatURL = chatViewController.currentAIChatURL
        }

        floatingWindowController = nil
        chatViewController = nil
        cancellables.removeAll()

        setHidden()
    }

#if DEBUG
    /// Test-only method to set the hiddenAt date for testing session timeout scenarios
    func updateHiddenAt(_ date: Date?) {
        hiddenAt = date
    }

    /// Test-only method to set the restoration data for testing
    func updateRestorationData(_ data: AIChatRestorationData?) {
        restorationData = data
    }
#endif
}

// MARK: - NSSecureCoding

extension AIChatState: NSSecureCoding {

    enum CodingKeys {
        static let initialAIChatURL = "initialAIChatURL"
        static let presentationMode = "presentationMode"
        static let hiddenAt = "hiddenAt"
        static let sidebarWidth = "sidebarWidth"
        // Legacy keys kept for backward-compatible encoding
        static let isPresented = "isPresented"
        static let isDetached = "isDetached"
    }

    convenience init?(coder: NSCoder) {
        let initialAIChatURL = coder.decodeObject(of: NSURL.self, forKey: CodingKeys.initialAIChatURL) as URL?
        self.init(initialAIChatURL: initialAIChatURL, burnerMode: .regular)
        self.presentationMode = Self.decodePresentationMode(from: coder)
        self.hiddenAt = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.hiddenAt) as Date?
        self.sidebarWidth = coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.sidebarWidth).map { CGFloat($0.doubleValue) }
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentAIChatURL as NSURL, forKey: CodingKeys.initialAIChatURL)
        coder.encode(presentationMode.rawValue, forKey: CodingKeys.presentationMode)
        coder.encode(hiddenAt as NSDate?, forKey: CodingKeys.hiddenAt)
        if let sidebarWidth {
            coder.encode(NSNumber(value: sidebarWidth), forKey: CodingKeys.sidebarWidth)
        }
        // Backward-compat: keep old keys so downgrades don't lose data
        coder.encode(isPresented, forKey: CodingKeys.isPresented)
        coder.encode(isDetached, forKey: CodingKeys.isDetached)
    }

    static var supportsSecureCoding: Bool {
        return true
    }
}

extension URL {

    enum AIChatPlacementParameter {
        public static let name = "placement"
        public static let sidebar = "sidebar"
    }

    public func forAIChatSidebar() -> URL {
        appendingParameter(name: AIChatPlacementParameter.name, value: AIChatPlacementParameter.sidebar)
    }

    public func removingAIChatPlacementParameter() -> URL {
        removingParameters(named: [AIChatPlacementParameter.name])
    }

    public var hasAIChatSidebarPlacementParameter: Bool {
        guard let parameter = self.getParameter(named: AIChatPlacementParameter.name) else {
            return false
        }
        return parameter == AIChatPlacementParameter.sidebar
    }
}
