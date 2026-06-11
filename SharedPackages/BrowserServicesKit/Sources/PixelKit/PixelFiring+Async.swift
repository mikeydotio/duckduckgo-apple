//
//  PixelFiring+Async.swift
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

extension PixelFiring {

    /// Async/await variant of PixelKit `fire`
    ///
    /// Note: Named `fireAsync` rather than overloading `fire` on purpose: a same-named `async` overload would be
    /// preferred by Swift over the synchronous `fire` inside any `async` context, silently breaking the many
    /// existing fire-and-forget `fire(...)` call sites that live in async code.
    ///
    /// - Returns: `true` if a request was fired, `false` if it was suppressed by frequency rules.
    /// - Throws: the underlying error if firing the request failed.
    @discardableResult
    public func fireAsync(_ event: PixelKitEvent,
                          frequency: PixelKit.Frequency = .standard,
                          includeAppVersionParameter: Bool = true,
                          withAdditionalParameters parameters: [String: String]? = nil,
                          withNamePrefix namePrefix: String? = nil) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            fire(event,
                 frequency: frequency,
                 includeAppVersionParameter: includeAppVersionParameter,
                 withAdditionalParameters: parameters,
                 withNamePrefix: namePrefix) { fired, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: fired)
            }
        }
    }
}
