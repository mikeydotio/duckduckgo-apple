//
//  RealDuckAILocalServer.swift
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
import DuckAILocalServerAPI
import FlyingFox
import FlyingSocks

public final class RealDuckAILocalServer: DuckAILocalServer, @unchecked Sendable {
    public private(set) var port: UInt16 = 0

    private let handlers: [DuckAIRequestHandler]
    private var server: HTTPServer?
    private var serverTask: Task<Void, any Error>?

    public init(handlers: [DuckAIRequestHandler]) {
        self.handlers = handlers
    }

    public static func makeDefault() -> RealDuckAILocalServer {
        let store = UserDefaultsDuckAISettingsStore()
        return RealDuckAILocalServer(handlers: [
            SettingsHandler(store: store),
            MigrationHandler(store: store),
        ])
    }

    public func start() async throws {
        guard server == nil else { return }

        let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: 0)
        let flyingFoxServer = HTTPServer(address: address, logger: .disabled)
        await flyingFoxServer.appendRoute("*") { [handlers] request in
            await Self.handleIncoming(request: request, handlers: handlers)
        }

        self.server = flyingFoxServer
        serverTask = Task {
            try await flyingFoxServer.run()
        }

        try await flyingFoxServer.waitUntilListening()

        if let listeningAddress = await flyingFoxServer.listeningAddress {
            switch listeningAddress {
            case .ip4(_, let listeningPort):
                port = listeningPort
            case .ip6(_, let listeningPort):
                port = listeningPort
            case .unix:
                break
            }
        }
    }

    public func stop() async {
        if let server {
            await server.stop(timeout: 0)
        }
        serverTask?.cancel()
        serverTask = nil
        server = nil
        port = 0
    }

    private static func handleIncoming(
        request: HTTPRequest,
        handlers: [DuckAIRequestHandler]
    ) async -> HTTPResponse {
        let origin = request.headers[HTTPHeader("Origin")]

        guard OriginValidator.isAllowed(origin: origin) else {
            return HTTPResponse(statusCode: .forbidden)
        }

        if request.method == .OPTIONS {
            var headers: HTTPHeaders = [:]
            headers[HTTPHeader("Access-Control-Allow-Origin")] = origin!
            headers[HTTPHeader("Access-Control-Allow-Methods")] = "GET, PUT, DELETE, POST, OPTIONS"
            headers[HTTPHeader("Access-Control-Allow-Headers")] = "Content-Type"
            headers[HTTPHeader("Access-Control-Max-Age")] = "86400"
            return HTTPResponse(statusCode: .noContent, headers: headers)
        }

        let uri = request.path

        guard let handler = handlers.first(where: { uri == $0.pathPrefix || uri.hasPrefix($0.pathPrefix + "/") }) else {
            return HTTPResponse(statusCode: .notFound)
        }

        let body = try? await request.bodyData
        let duckResponse = await handler.handle(method: request.method.rawValue, uri: uri, body: body)

        var responseHeaders: HTTPHeaders = [:]
        responseHeaders[HTTPHeader("Access-Control-Allow-Origin")] = origin!
        responseHeaders[HTTPHeader("Access-Control-Allow-Methods")] = "GET, PUT, DELETE, POST, OPTIONS"
        responseHeaders[HTTPHeader("Access-Control-Allow-Headers")] = "Content-Type"

        for (key, value) in duckResponse.headers {
            responseHeaders[HTTPHeader(key)] = value
        }

        let statusCode = HTTPStatusCode(duckResponse.statusCode, phrase: "")
        return HTTPResponse(statusCode: statusCode, headers: responseHeaders, body: duckResponse.body ?? Data())
    }
}
