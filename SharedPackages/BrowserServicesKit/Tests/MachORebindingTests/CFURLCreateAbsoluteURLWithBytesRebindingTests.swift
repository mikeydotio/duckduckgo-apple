//
//  CFURLCreateAbsoluteURLWithBytesRebindingTests.swift
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

@testable import Common
import CoreFoundation
import MachO
import WebKit
import XCTest

private typealias CFURLCreateAbsoluteURLWithBytesFunction = @convention(c) (
    CFAllocator?,
    UnsafePointer<UInt8>?,
    CFIndex,
    CFStringEncoding,
    CFURL?,
    Bool
) -> CFURL?

private nonisolated(unsafe) var originalFunction: CFURLCreateAbsoluteURLWithBytesFunction?
private nonisolated(unsafe) var hookCallCount = 0

private nonisolated(unsafe) let replacementFunction: CFURLCreateAbsoluteURLWithBytesFunction = { allocator, bytes, length, encoding, baseURL, useCompatibilityMode in
    hookCallCount += 1

    return originalFunction?(
        allocator,
        bytes,
        length,
        encoding,
        baseURL,
        useCompatibilityMode
    )
}

final class CFURLCreateAbsoluteURLWithBytesRebindingTests: XCTestCase {

    private var originalsByImage = [UnsafeRawPointer: UnsafeRawPointer]()

    override func tearDownWithError() throws {
        try restoreOriginalFunction()
        hookCallCount = 0
        originalFunction = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testPatchesWebKitImportAndIsHitByWebViewNavigation() throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let delegate = WebViewNavigationDelegate()
        webView.navigationDelegate = delegate
        printLoadedWebKitImages()

        let replacement = unsafeBitCast(replacementFunction, to: UnsafeRawPointer.self)

        let patchedImages = try rebindLoadedImages(
            symbol: "CFURLCreateAbsoluteURLWithBytes",
            replacement: replacement,
            originals: &originalsByImage,
            shouldPatchImage: isWebKitImage
        )

        print("CFURLCreateAbsoluteURLWithBytes patched images: \(patchedImages)")
        print("CFURLCreateAbsoluteURLWithBytes originalsByImage count: \(originalsByImage.count)")

        originalFunction = unsafeBitCast(try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CFURLCreateAbsoluteURLWithBytes")),
                                         to: CFURLCreateAbsoluteURLWithBytesFunction.self)

        XCTAssertEqual(patchedImages, ["WebKit"])

        let didFinish = expectation(description: "Initial page loaded")
        delegate.didFinish = { didFinish.fulfill() }
        webView.loadHTMLString("<!doctype html><title>ready</title>", baseURL: URL(string: "https://example.com/")!)
        wait(for: [didFinish], timeout: 5)

        hookCallCount = 0
        let didRequestCustomSchemeNavigation = expectation(description: "WebKit parsed custom-scheme navigation URL")
        delegate.decidePolicy = { navigationAction, decisionHandler in
            if navigationAction.request.url?.scheme == "duck-fragment-test" {
                didRequestCustomSchemeNavigation.fulfill()
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        webView.evaluateJavaScript("window.location.href = 'duck-fragment-test:opaque/path#frag';")
        wait(for: [didRequestCustomSchemeNavigation], timeout: 5)

        XCTAssertGreaterThan(hookCallCount, 0)
    }

    private func restoreOriginalFunction() throws {
        guard let originalFunction else { return }

        var discardedOriginals = [UnsafeRawPointer: UnsafeRawPointer]()
        let original = unsafeBitCast(originalFunction, to: UnsafeRawPointer.self)
        try rebindLoadedImages(
            symbol: "CFURLCreateAbsoluteURLWithBytes",
            replacement: original,
            originals: &discardedOriginals,
            shouldPatchImage: isWebKitImage
        )
        originalsByImage.removeAll()
    }

    @discardableResult
    private func rebindLoadedImages(symbol: String,
                                    replacement: UnsafeRawPointer,
                                    originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                                    shouldPatchImage: (String) -> Bool) throws -> [String] {
        var patchedImages = [String]()

        for imageIndex in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(imageIndex) else { continue }
            let imageName = _dyld_get_image_name(imageIndex).map(String.init(cString:)) ?? "<unknown>"
            let lastPathComponent = (imageName as NSString).lastPathComponent
            guard shouldPatchImage(lastPathComponent) else { continue }

            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            guard let imageMap = ImageMap(header: header64, slide: _dyld_get_image_vmaddr_slide(imageIndex)) else {
                continue
            }

            let patched = try imageMap.rebindSymbol(
                symbol,
                slide: _dyld_get_image_vmaddr_slide(imageIndex),
                to: replacement,
                savingOriginalTo: &originals,
                patchDyldCacheStubTargets: true
            )
            if patched {
                patchedImages.append(lastPathComponent)
            }
        }

        return patchedImages
    }

    private func printLoadedWebKitImages() {
        var images = [String]()
        for imageIndex in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(imageIndex),
                  let imageNamePointer = _dyld_get_image_name(imageIndex) else { continue }
            let imageName = String(cString: imageNamePointer)
            guard imageName.localizedCaseInsensitiveContains("WebKit") ||
                    imageName.localizedCaseInsensitiveContains("WebCore") else { continue }

            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            let imageMap = ImageMap(header: header64, slide: _dyld_get_image_vmaddr_slide(imageIndex))
            images.append("\((imageName as NSString).lastPathComponent): imageMap=\(imageMap != nil) chained=\(imageMap?.chainedFixupsCmd != nil)")
        }
        print("Loaded WebKit/WebCore images: \(images)")
    }

    private func isWebKitImage(_ imageName: String) -> Bool {
        imageName == "WebKit"
    }
}

@MainActor
private final class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {

    var didFinish: (() -> Void)?
    var decidePolicy: ((WKNavigationAction, @escaping (WKNavigationActionPolicy) -> Void) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decidePolicy?(navigationAction, decisionHandler) ?? decisionHandler(.allow)
    }
}
