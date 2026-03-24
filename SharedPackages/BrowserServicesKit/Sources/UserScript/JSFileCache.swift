//
//  JSFileCache.swift
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

enum JSFileCache {

    private static let lock = NSLock()
    private static var storage = [String: String]()

    static func content(forFile file: String, in bundle: Bundle) throws -> String {
        let cacheKey = bundle.bundlePath + "/" + file

        lock.lock()
        let cached = storage[cacheKey]
        lock.unlock()

        if let cached { return cached }

        guard let path = bundle.path(forResource: file, ofType: "js") else {
            throw UserScriptError.failedToLoadJS(jsFile: file, error: CocoaError(.fileReadNoSuchFile))
        }

        do {
            let content = try String(contentsOfFile: path)
            lock.lock()
            storage[cacheKey] = content
            lock.unlock()
            return content
        } catch {
            throw UserScriptError.failedToLoadJS(jsFile: file, error: error)
        }
    }

    /// Single-pass replacement of `$TOKEN$`-style placeholders.
    /// Scans the template's UTF-8 bytes once, matching replacement keys
    /// at every `$` and copying non-matching regions in bulk.
    static func applyReplacements(_ template: String, _ replacements: [String: String]) -> String {
        guard !replacements.isEmpty else { return template }

        let templateUTF8 = Array(template.utf8)
        let dollar = UInt8(ascii: "$")
        let keys = replacements.map { (utf8: Array($0.key.utf8), value: Array($0.value.utf8)) }

        var result = [UInt8]()
        result.reserveCapacity(templateUTF8.count)

        var i = 0
        while i < templateUTF8.count {
            if templateUTF8[i] == dollar {
                var matched = false
                for entry in keys {
                    let end = i + entry.utf8.count
                    if end <= templateUTF8.count,
                       templateUTF8[i..<end].elementsEqual(entry.utf8) {
                        result.append(contentsOf: entry.value)
                        i = end
                        matched = true
                        break
                    }
                }
                if !matched {
                    result.append(templateUTF8[i])
                    i += 1
                }
            } else {
                let start = i
                while i < templateUTF8.count && templateUTF8[i] != dollar {
                    i += 1
                }
                result.append(contentsOf: templateUTF8[start..<i])
            }
        }

        return String(decoding: result, as: UTF8.self)
    }
}
