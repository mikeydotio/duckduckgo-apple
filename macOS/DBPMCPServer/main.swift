//
//  main.swift
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

/// Debug-only MCP server for PIR (Data Broker Protection) debugging.
///
/// Communicates with Claude Code over stdio (JSON-RPC 2.0) and connects to the
/// PIR background agent via XPC to query state, trigger operations, and read logs.
///
/// Usage:
///   dbp-mcp-server [--mach-service <name>]

// MARK: - Argument Parsing

func parseMachServiceName() -> String {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--mach-service"), idx + 1 < args.count {
        return args[idx + 1]
    }
    return "com.duckduckgo.macos.DBP.backgroundAgent.debug"
}

// MARK: - Entry Point

let machServiceName = parseMachServiceName()

func log(_ message: String) {
    let data = (message + "\n").data(using: .utf8)!
    FileHandle.standardError.write(data)
}

log("dbp-mcp-server starting (mach service: \(machServiceName))")

let agent = AgentConnection(machServiceName: machServiceName)
let tools = MCPTools(agent: agent)
let server = MCPServer(tools: tools)

server.run()

dispatchMain()
