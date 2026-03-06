//
//  BrowserMCPServer.swift
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

#if DEBUG

import AppKit
import BrowserMCPCommon
import Combine
import os.log
import UDSHelper
import WebKit

final class BrowserMCPServer {

    private let server: UDSServer
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "BrowserMCPServer")

    init() {
        let socketURL = URL(fileURLWithPath: MCPSocketConstants.socketPath)
        self.server = UDSServer(socketFileURL: socketURL)
    }

    func start() throws {
        try server.start { [weak self] data in
            guard let self else { return nil }
            return try await self.handleMessage(data)
        }
        Self.logger.info("BrowserMCPServer started on \(MCPSocketConstants.socketPath, privacy: .public)")
    }

    private func handleMessage(_ data: Data) async throws -> Data? {
        let command = try JSONDecoder().decode(MCPCommand.self, from: data)
        do {
            let response = try await executeCommand(command)
            return try JSONEncoder().encode(response)
        } catch let error as BrowserMCPError {
            return try JSONEncoder().encode(error)
        }
    }

    @MainActor
    private func executeCommand(_ command: MCPCommand) async throws -> MCPResponse {
        switch command {
        case .navigate(let url):
            return try await handleNavigate(url: url)
        case .goBack:
            return try await handleGoBack()
        case .goForward:
            return try await handleGoForward()
        case .screenshot(let width):
            return try await handleScreenshot(width: width)
        case .tabList:
            return try handleTabList()
        case .tabSwitch(let index):
            return try handleTabSwitch(index: index)
        case .tabClose(let index):
            return try handleTabClose(index: index)
        case .tabNew(let url):
            return try handleTabNew(url: url)
        case .scroll(let x, let y):
            return try handleScroll(deltaX: x, deltaY: y)
        }
    }

    // MARK: - Navigation

    @MainActor
    private func handleNavigate(url urlString: String) async throws -> MCPResponse {
        guard let url = URL(string: urlString) else {
            throw BrowserMCPError.invalidURL
        }
        let tab = try activeTab()
        tab.setContent(.url(url, source: .link))
        try await waitForLoadToFinish(tab: tab)
        return .navigation(.init(url: tab.content.urlForWebView?.absoluteString, title: tab.title))
    }

    @MainActor
    private func handleGoBack() async throws -> MCPResponse {
        let tab = try activeTab()
        tab.goBack()
        try await waitForLoadToFinish(tab: tab)
        return .navigation(.init(url: tab.content.urlForWebView?.absoluteString, title: tab.title))
    }

    @MainActor
    private func handleGoForward() async throws -> MCPResponse {
        let tab = try activeTab()
        tab.goForward()
        try await waitForLoadToFinish(tab: tab)
        return .navigation(.init(url: tab.content.urlForWebView?.absoluteString, title: tab.title))
    }

    // MARK: - Screenshot

    @MainActor
    private func handleScreenshot(width: Int?) async throws -> MCPResponse {
        let tab = try activeTab()
        let webView = tab.webView

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(integerLiteral: width ?? 1280)

        let image = try await webView.takeSnapshot(configuration: config)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw BrowserMCPError.screenshotFailed("Failed to encode screenshot as PNG")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ddg-mcp-\(UUID().uuidString).png")
        try pngData.write(to: tempURL)
        return .screenshot(.init(filePath: tempURL.path))
    }

    // MARK: - Tabs

    @MainActor
    private func handleTabList() throws -> MCPResponse {
        let tabVM = try activeTabCollectionViewModel()
        let tabs = tabVM.tabCollection.tabs
        let selectedIndex = tabVM.selectionIndex

        let tabInfos: [MCPResponse.TabInfo] = tabs.enumerated().map { index, tab in
            MCPResponse.TabInfo(
                index: index,
                title: tab.title,
                url: tab.content.urlForWebView?.absoluteString,
                isActive: selectedIndex == .unpinned(index)
            )
        }
        return .tabList(tabInfos)
    }

    @MainActor
    private func handleTabSwitch(index: Int) throws -> MCPResponse {
        let tabVM = try activeTabCollectionViewModel()
        guard index >= 0 && index < tabVM.tabCollection.tabs.count else {
            throw BrowserMCPError.tabNotFound
        }
        tabVM.select(at: .unpinned(index))
        let tab = tabVM.tabCollection.tabs[index]
        return .navigation(.init(url: tab.content.urlForWebView?.absoluteString, title: tab.title))
    }

    @MainActor
    private func handleTabClose(index: Int?) throws -> MCPResponse {
        let tabVM = try activeTabCollectionViewModel()
        if let index {
            guard index >= 0 && index < tabVM.tabCollection.tabs.count else {
                throw BrowserMCPError.tabNotFound
            }
            tabVM.remove(at: .unpinned(index))
        } else {
            guard let selectionIndex = tabVM.selectionIndex else {
                throw BrowserMCPError.noActiveTab
            }
            tabVM.remove(at: selectionIndex)
        }
        return .success
    }

    @MainActor
    private func handleTabNew(url urlString: String?) throws -> MCPResponse {
        let tabVM = try activeTabCollectionViewModel()
        if let urlString, let url = URL(string: urlString) {
            tabVM.appendNewTab(with: .url(url, source: .link))
        } else {
            tabVM.appendNewTab()
        }
        let index = tabVM.tabCollection.tabs.count - 1
        let tab = tabVM.tabCollection.tabs[index]
        return .tabNew(.init(index: index, url: tab.content.urlForWebView?.absoluteString))
    }

    // MARK: - Scroll

    @MainActor
    private func handleScroll(deltaX: Double, deltaY: Double) throws -> MCPResponse {
        let tab = try activeTab()
        let webView = tab.webView
        let center = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)

        guard let event = NSEvent.mouseEvent(
            with: .scrollWheel,
            location: center,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: webView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) else {
            return .success
        }

        // NSEvent.mouseEvent doesn't set scroll deltas, so we use CGEvent
        guard let cgEvent = event.cgEvent else {
            return .success
        }
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        guard let scrollEvent = NSEvent(cgEvent: cgEvent) else {
            return .success
        }

        webView.scrollWheel(with: scrollEvent)
        return .success
    }

    // MARK: - Helpers

    @MainActor
    private func activeTab() throws -> Tab {
        let tabVM = try activeTabCollectionViewModel()
        guard let tab = tabVM.selectedTabViewModel?.tab else {
            throw BrowserMCPError.noActiveTab
        }
        return tab
    }

    @MainActor
    private func activeTabCollectionViewModel() throws -> TabCollectionViewModel {
        let windowManager = Application.appDelegate.windowControllersManager
        guard let mainWC = windowManager.mainWindowController ?? windowManager.mainWindowControllers.first else {
            throw BrowserMCPError.noActiveTab
        }
        return mainWC.mainViewController.tabCollectionViewModel
    }

    @MainActor
    private func waitForLoadToFinish(tab: Tab) async throws {
        guard tab.isLoading else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    var cancellable: AnyCancellable?
                    cancellable = tab.$isLoading.sink { isLoading in
                        if !isLoading {
                            cancellable?.cancel()
                            continuation.resume()
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw BrowserMCPError.timeout
            }

            try await group.next()
            group.cancelAll()
        }
    }
}

#endif
