//
//  RemoteImageAttachmentFetcher.swift
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

import UIKit

/// Downloads a remote image so it can be attached to a Duck.ai prompt.
///
/// Used by the in-page "Ask Duck.ai" long-press action: JavaScript resolves the
/// `src` of the long-pressed image, and this type re-downloads the bytes (sharing the
/// originating web view's cookies via the injected `URLSession`) and decodes a `UIImage`.
struct RemoteImageAttachmentFetcher {

    enum FetchError: Error {
        case unsuccessfulResponse
        case notAnImage
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Downloads and decodes the image at `url`.
    /// - Returns: the decoded image and a display file name derived from the URL.
    func fetchImage(from url: URL) async throws -> (image: UIImage, fileName: String) {
        let (data, response) = try await urlSession.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FetchError.unsuccessfulResponse
        }

        guard let image = UIImage(data: data) else {
            throw FetchError.notAnImage
        }

        return (image, Self.fileName(for: url))
    }

    private static func fileName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        guard !lastPathComponent.isEmpty, lastPathComponent != "/" else {
            return "image"
        }
        return lastPathComponent
    }
}
