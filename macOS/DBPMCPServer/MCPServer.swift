//
//  MCPServer.swift
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

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let method: String
    let id: JSONRPCId?
    let params: [String: AnyCodable]?
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCId?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Encodable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

enum JSONRPCId: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - MCP Server

/// Implements the MCP protocol over stdin/stdout using JSON-RPC 2.0.
final class MCPServer {
    private let tools: MCPTools
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let pendingRequests = DispatchGroup()

    init(tools: MCPTools) {
        self.tools = tools
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    func run() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            self.readLoop()
        }
    }

    private func readLoop() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: data)
                handleRequest(request)
            } catch {
                let response = JSONRPCResponse(
                    id: nil,
                    result: nil,
                    error: JSONRPCError(code: -32700, message: "Parse error: \(error.localizedDescription)", data: nil)
                )
                send(response)
            }
        }

        pendingRequests.wait()
        fflush(stdout)
        Thread.sleep(forTimeInterval: 0.2)
        Darwin.exit(0)
    }

    // MARK: - Request Dispatch

    private func handleRequest(_ request: JSONRPCRequest) {
        switch request.method {
        case "initialize":
            handleInitialize(request)
        case "initialized", "notifications/initialized":
            break
        case "tools/list":
            handleToolsList(request)
        case "tools/call":
            handleToolsCall(request)
        case "ping":
            respond(to: request, result: AnyCodable([:] as [String: Any]))
        default:
            let response = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)", data: nil)
            )
            send(response)
        }
    }

    // MARK: - MCP Protocol Handlers

    private func handleInitialize(_ request: JSONRPCRequest) {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "dbp-mcp-server", "version": "1.0.0"]
        ]
        respond(to: request, result: AnyCodable(result))
    }

    private func handleToolsList(_ request: JSONRPCRequest) {
        let toolDefinitions = tools.listTools()
        respond(to: request, result: AnyCodable(["tools": toolDefinitions]))
    }

    private func handleToolsCall(_ request: JSONRPCRequest) {
        guard let params = request.params,
              let toolName = params["name"]?.value as? String else {
            let response = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32602, message: "Missing 'name' in tools/call params", data: nil)
            )
            send(response)
            return
        }

        let arguments = params["arguments"]?.value as? [String: Any] ?? [:]

        pendingRequests.enter()
        tools.callTool(name: toolName, arguments: arguments) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let text):
                let content: [[String: Any]] = [["type": "text", "text": text]]
                self.respond(to: request, result: AnyCodable(["content": content]))

            case .failure(let error):
                let content: [[String: Any]] = [["type": "text", "text": "Error: \(error.localizedDescription)"]]
                self.respond(to: request, result: AnyCodable(["content": content, "isError": true]))
            }

            self.pendingRequests.leave()
        }
    }

    // MARK: - Response Helpers

    private func respond(to request: JSONRPCRequest, result: AnyCodable) {
        let response = JSONRPCResponse(id: request.id, result: result, error: nil)
        send(response)
    }

    private let outputLock = NSLock()

    private func send(_ response: JSONRPCResponse) {
        do {
            let data = try encoder.encode(response)
            guard var jsonString = String(data: data, encoding: .utf8) else { return }
            jsonString += "\n"
            outputLock.lock()
            jsonString.withCString { ptr in
                let len = strlen(ptr)
                var written = 0
                while written < len {
                    let result = Darwin.write(STDOUT_FILENO, ptr + written, len - written)
                    if result <= 0 { break }
                    written += result
                }
            }
            outputLock.unlock()
        } catch {
            log("Failed to encode response: \(error)")
        }
    }
}
