//
//  BrowserMCPToolRegistration.swift
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
import MCP
import BrowserMCPCommon

enum BrowserMCPToolRegistration {

    static func registerTools(on server: Server, client: UDSBrowserClient) async {

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            try await Self.handleToolCall(params: params, client: client)
        }
    }

    // MARK: - Tool Definitions

    private static let toolDefinitions: [Tool] = [
        Tool(
            name: "browser_navigate",
            description: "Navigate the active tab to a URL",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to navigate to"]
                ],
                "required": .array([.string("url")])
            ])
        ),
        Tool(
            name: "browser_go_back",
            description: "Go back in the active tab's history",
            inputSchema: .object(["type": "object", "properties": [:]])
        ),
        Tool(
            name: "browser_go_forward",
            description: "Go forward in the active tab's history",
            inputSchema: .object(["type": "object", "properties": [:]])
        ),
        Tool(
            name: "browser_screenshot",
            description: "Take a screenshot of the active tab",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "width": ["type": "number", "description": "Screenshot width in pixels (default: 1280)"]
                ]
            ])
        ),
        Tool(
            name: "browser_tab_list",
            description: "List all open tabs in the current window",
            inputSchema: .object(["type": "object", "properties": [:]])
        ),
        Tool(
            name: "browser_tab_switch",
            description: "Switch to a tab by index",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "index": ["type": "number", "description": "The tab index to switch to (0-based)"]
                ],
                "required": .array([.string("index")])
            ])
        ),
        Tool(
            name: "browser_tab_close",
            description: "Close a tab by index (default: active tab)",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "index": ["type": "number", "description": "The tab index to close (0-based). If omitted, closes the active tab."]
                ]
            ])
        ),
        Tool(
            name: "browser_tab_new",
            description: "Open a new tab, optionally with a URL",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL to open in the new tab"]
                ]
            ])
        ),
        Tool(
            name: "browser_scroll",
            description: "Scroll the active tab's page. Positive y scrolls down, negative y scrolls up. Positive x scrolls right, negative x scrolls left.",
            inputSchema: .object([
                "type": "object",
                "properties": [
                    "x": ["type": "number", "description": "Horizontal scroll amount in pixels (default: 0)"],
                    "y": ["type": "number", "description": "Vertical scroll amount in pixels (default: 0)"]
                ]
            ])
        ),
    ]

    // MARK: - Tool Call Dispatch

    private static func handleToolCall(params: CallTool.Parameters, client: UDSBrowserClient) async throws -> CallTool.Result {
        do {
            switch params.name {
            case "browser_navigate":
                guard let url = params.arguments?["url"]?.stringValue else {
                    return .init(content: [.text("Missing required parameter: url")], isError: true)
                }
                let response = try await client.send(.navigate(url: url))
                return .init(content: formatNavigation(response))

            case "browser_go_back":
                let response = try await client.send(.goBack)
                return .init(content: formatNavigation(response))

            case "browser_go_forward":
                let response = try await client.send(.goForward)
                return .init(content: formatNavigation(response))

            case "browser_screenshot":
                let width = params.arguments?["width"]?.intValue
                let response = try await client.send(.screenshot(width: width))
                guard case .screenshot(let result) = response else {
                    return .init(content: [.text("Screenshot failed")], isError: true)
                }
                let fileURL = URL(fileURLWithPath: result.filePath)
                let pngData = try Data(contentsOf: fileURL)
                try? FileManager.default.removeItem(at: fileURL)
                let base64 = pngData.base64EncodedString()
                return .init(content: [.image(data: base64, mimeType: "image/png", metadata: nil)])

            case "browser_tab_list":
                let response = try await client.send(.tabList)
                guard case .tabList(let tabs) = response else {
                    return .init(content: [.text("Failed to list tabs")], isError: true)
                }
                let json = try JSONEncoder().encode(tabs)
                return .init(content: [.text(String(data: json, encoding: .utf8) ?? "[]")])

            case "browser_tab_switch":
                guard let index = params.arguments?["index"]?.intValue else {
                    return .init(content: [.text("Missing required parameter: index")], isError: true)
                }
                let response = try await client.send(.tabSwitch(index: index))
                return .init(content: formatNavigation(response))

            case "browser_tab_close":
                let index = params.arguments?["index"]?.intValue
                _ = try await client.send(.tabClose(index: index))
                return .init(content: [.text("{\"success\": true}")])

            case "browser_tab_new":
                let url = params.arguments?["url"]?.stringValue
                let response = try await client.send(.tabNew(url: url))
                guard case .tabNew(let result) = response else {
                    return .init(content: [.text("Failed to open new tab")], isError: true)
                }
                let json = try JSONEncoder().encode(result)
                return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")])

            case "browser_scroll":
                let x = params.arguments?["x"]?.doubleValue ?? 0
                let y = params.arguments?["y"]?.doubleValue ?? 0
                _ = try await client.send(.scroll(x: x, y: y))
                return .init(content: [.text("{\"success\": true}")])

            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        } catch let error as BrowserMCPError {
            return .init(content: [.text("Error: \(error)")], isError: true)
        }
    }

    // MARK: - Helpers

    private static func formatNavigation(_ response: MCPResponse) -> [Tool.Content] {
        guard case .navigation(let result) = response else {
            return [.text("{}")]
        }
        let json = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [.text(json)]
    }
}
