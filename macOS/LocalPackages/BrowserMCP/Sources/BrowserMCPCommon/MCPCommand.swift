//
//  MCPCommand.swift
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

import Foundation

public enum MCPCommand: Codable, Sendable {
    case navigate(url: String)
    case goBack
    case goForward
    case screenshot(width: Int?)
    case tabList
    case tabSwitch(index: Int)
    case tabClose(index: Int?)
    case tabNew(url: String?)
    case scroll(x: Double, y: Double)
}

public enum MCPResponse: Codable, Sendable {
    case navigation(NavigationResult)
    case screenshot(ScreenshotResult)
    case tabList([TabInfo])
    case tabNew(NewTabResult)
    case success

    public struct NavigationResult: Codable, Sendable {
        public var url: String?
        public var title: String?

        public init(url: String?, title: String?) {
            self.url = url
            self.title = title
        }
    }

    public struct ScreenshotResult: Codable, Sendable {
        public var filePath: String

        public init(filePath: String) {
            self.filePath = filePath
        }
    }

    public struct TabInfo: Codable, Sendable {
        public var index: Int
        public var title: String?
        public var url: String?
        public var isActive: Bool

        public init(index: Int, title: String?, url: String?, isActive: Bool) {
            self.index = index
            self.title = title
            self.url = url
            self.isActive = isActive
        }
    }

    public struct NewTabResult: Codable, Sendable {
        public var index: Int
        public var url: String?

        public init(index: Int, url: String?) {
            self.index = index
            self.url = url
        }
    }
}

public enum BrowserMCPError: Codable, Sendable, Error {
    case browserNotRunning
    case noActiveTab
    case invalidURL
    case navigationFailed(String)
    case screenshotFailed(String)
    case tabNotFound
    case timeout
}

public enum MCPSocketConstants {
    public static let socketPath = "/tmp/ddg-mcp.sock"
}
