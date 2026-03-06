//
//  UDSBrowserClient.swift
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
import BrowserMCPCommon
import UDSHelper

actor UDSBrowserClient {
    private let client: UDSClient

    init() {
        let socketURL = URL(fileURLWithPath: MCPSocketConstants.socketPath)
        self.client = UDSClient(socketFileURL: socketURL)
    }

    func send(_ command: MCPCommand) async throws -> MCPResponse {
        let requestData = try JSONEncoder().encode(command)
        guard let responseData = try await client.send(requestData) else {
            throw BrowserMCPError.browserNotRunning
        }

        if let error = try? JSONDecoder().decode(BrowserMCPError.self, from: responseData) {
            throw error
        }

        return try JSONDecoder().decode(MCPResponse.self, from: responseData)
    }
}
