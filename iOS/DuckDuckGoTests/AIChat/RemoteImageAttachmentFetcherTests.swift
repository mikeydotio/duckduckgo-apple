//
//  RemoteImageAttachmentFetcherTests.swift
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

import NetworkingTestingUtils
import UIKit
import XCTest
@testable import DuckDuckGo

final class RemoteImageAttachmentFetcherTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func testWhenURLReturnsValidImageThenReturnsImageAndFileNameFromURL() async throws {
        let imageData = Self.makeImageData()
        MockURLProtocol.requestHandler = { request in
            (Self.okResponse(for: request), imageData)
        }
        let fetcher = RemoteImageAttachmentFetcher(urlSession: session)

        let result = try await fetcher.fetchImage(from: URL(string: "https://example.com/photos/cat.png?size=large")!)

        XCTAssertEqual(result.fileName, "cat.png")
        XCTAssertGreaterThan(result.image.size.width, 0)
    }

    func testWhenURLHasNoFileNameThenUsesDefaultFileName() async throws {
        let imageData = Self.makeImageData()
        MockURLProtocol.requestHandler = { request in
            (Self.okResponse(for: request), imageData)
        }
        let fetcher = RemoteImageAttachmentFetcher(urlSession: session)

        let result = try await fetcher.fetchImage(from: URL(string: "https://example.com/")!)

        XCTAssertEqual(result.fileName, "image")
    }

    func testWhenResponseStatusIsNotSuccessfulThenThrowsUnsuccessfulResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }
        let fetcher = RemoteImageAttachmentFetcher(urlSession: session)

        do {
            _ = try await fetcher.fetchImage(from: URL(string: "https://example.com/cat.png")!)
            XCTFail("Expected fetchImage to throw")
        } catch RemoteImageAttachmentFetcher.FetchError.unsuccessfulResponse {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenDataIsNotAnImageThenThrowsNotAnImage() async {
        MockURLProtocol.requestHandler = { request in
            (Self.okResponse(for: request), Data("definitely not an image".utf8))
        }
        let fetcher = RemoteImageAttachmentFetcher(urlSession: session)

        do {
            _ = try await fetcher.fetchImage(from: URL(string: "https://example.com/cat.png")!)
            XCTFail("Expected fetchImage to throw")
        } catch RemoteImageAttachmentFetcher.FetchError.notAnImage {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private static func okResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private static func makeImageData() -> Data {
        let size = CGSize(width: 2, height: 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }
}
