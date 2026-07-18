//
//  UnifiedToggleInputPasteHandler.swift
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

import AIChat
import UIKit
import UniformTypeIdentifiers

/// Injected into the shared text controls so a native image/file paste is routed into the attachment strip; `nil` on non-UTI hosts leaves default text paste untouched.
@MainActor
protocol AttachmentPasteHandling: AnyObject {

    /// Whether the pasteboard holds image/file content that can become an attachment; metadata-only, safe from `canPerformAction(_:withSender:)`.
    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool

    /// Turns supported pasteboard items into attachments; loads asynchronously.
    func pasteAttachments(from pasteboard: UIPasteboard)
}

/// Shared `paste(_:)` / `canPerformAction(_:)` routing so the two text controls don't duplicate the logic.
@MainActor
enum AttachmentPasteRouting {

    static func canPaste(with handler: AttachmentPasteHandling?) -> Bool {
        handler?.canPasteAttachments(from: .general) ?? false
    }

    /// Routes the general pasteboard to the handler; returns `false` when the caller should fall back to the default paste.
    static func routePaste(with handler: AttachmentPasteHandling?) -> Bool {
        guard let handler, handler.canPasteAttachments(from: .general) else { return false }
        handler.pasteAttachments(from: .general)
        return true
    }
}

/// What the current model accepts plus the remaining headroom, snapshotted once per paste so the loader can preflight sizes/counts.
struct UnifiedToggleInputPasteSupport {
    let isEnabled: Bool
    let acceptsImages: Bool
    let fileTypes: [UTType]
    /// Number of images the loader may decode before it stops, so a paste of many photos can't over-allocate.
    let maxImageCount: Int?
    /// Per-file byte limit, used to reject an oversized paste from its size alone before reading it into memory.
    let maxFileSizeBytes: Int?
    /// Remaining conversation file slots; the loader stops reading once exhausted so a large multi-file paste can't over-allocate.
    let remainingFileCount: Int?
    /// Remaining conversation file bytes; the loader reads only files that fit within this budget.
    let remainingTotalFileBytes: Int?

    init(
        isEnabled: Bool,
        acceptsImages: Bool,
        fileTypes: [UTType],
        maxImageCount: Int? = nil,
        maxFileSizeBytes: Int? = nil,
        remainingFileCount: Int? = nil,
        remainingTotalFileBytes: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.acceptsImages = acceptsImages
        self.fileTypes = fileTypes
        self.maxImageCount = maxImageCount
        self.maxFileSizeBytes = maxFileSizeBytes
        self.remainingFileCount = remainingFileCount
        self.remainingTotalFileBytes = remainingTotalFileBytes
    }

    var acceptsAnyAttachment: Bool { acceptsImages || !fileTypes.isEmpty }
}

/// The host the paste handler calls back into to read limits and add/report attachments (the coordinator).
@MainActor
protocol UnifiedToggleInputPasteDelegate: AnyObject {
    var pasteAttachmentSupport: UnifiedToggleInputPasteSupport { get }
    /// Identity of the tab/surface the paste started on; the handler drops results if it changed during the async load.
    var pasteContextIdentity: String? { get }
    func imageCapacityMessage() -> String?
    func pasteWillBeginExpandingIfNeeded()
    /// Adds the image if there is headroom; returns `false` when the image limit is reached.
    @discardableResult func addPastedImage(_ image: UIImage, fileName: String) -> Bool
    func addPastedFile(_ file: AIChatFileAttachment)
    /// Adds a file that was rejected during load (over size/count/total) as an invalid attachment; never becomes a valid file.
    func addRejectedPastedFile(fileName: String, mimeType: String, fileSizeBytes: Int)
    func presentPasteError(_ message: String)
}

/// Owns the paste orchestration (gate → load → add → report) so the coordinator only supplies limits and add actions via `UnifiedToggleInputPasteDelegate`.
@MainActor
final class UnifiedToggleInputPasteHandler: AttachmentPasteHandling {

    weak var delegate: UnifiedToggleInputPasteDelegate?

    func canPasteAttachments(from pasteboard: UIPasteboard) -> Bool {
        guard let support = delegate?.pasteAttachmentSupport, support.isEnabled, support.acceptsAnyAttachment else { return false }
        return PasteboardAttachmentReader.hasSupportedAttachments(
            in: pasteboard,
            allowsImages: support.acceptsImages,
            allowedFileTypes: support.fileTypes
        )
    }

    func pasteAttachments(from pasteboard: UIPasteboard) {
        guard let delegate else { return }
        let support = delegate.pasteAttachmentSupport
        guard support.isEnabled, support.acceptsAnyAttachment else { return }
        let providers = pasteboard.itemProviders
        let hasStrings = pasteboard.hasStrings
        let context = delegate.pasteContextIdentity
        delegate.pasteWillBeginExpandingIfNeeded()
        Task { [weak self] in
            let result = await PasteboardAttachmentReader.loadAttachments(
                from: providers,
                allowsImages: support.acceptsImages,
                allowedFileTypes: support.fileTypes,
                maxImageCount: support.maxImageCount,
                maxFileSizeBytes: support.maxFileSizeBytes,
                remainingFileCount: support.remainingFileCount,
                remainingTotalFileBytes: support.remainingTotalFileBytes,
                pasteboardHasStrings: hasStrings
            )
            self?.applyLoadedAttachments(result, expectedContext: context)
        }
    }

    /// Applied after the async load; drops the result if paste was disabled or the tab/conversation changed during the load. Files first so a rejected image's limit message (presented last) survives a following file add.
    func applyLoadedAttachments(_ result: PasteboardAttachmentReader.Result, expectedContext: String? = nil) {
        guard let delegate,
              delegate.pasteAttachmentSupport.isEnabled,
              delegate.pasteContextIdentity == expectedContext else { return }

        for file in result.files {
            delegate.addPastedFile(file)
        }

        if let rejected = result.rejectedFile {
            delegate.addRejectedPastedFile(fileName: rejected.fileName, mimeType: rejected.mimeType, fileSizeBytes: rejected.fileSizeBytes)
        }

        var didExceedImageLimit = false
        for image in result.images {
            guard delegate.addPastedImage(image.image, fileName: image.fileName) else {
                didExceedImageLimit = true
                break
            }
        }

        if didExceedImageLimit || result.imagesTruncated, let message = delegate.imageCapacityMessage() {
            delegate.presentPasteError(message)
        }
    }
}

/// Extracts image/file attachments from a `UIPasteboard`, mirroring the picker paths so pasted content flows through the same validation and UI as the attach menu.
@MainActor
enum PasteboardAttachmentReader {

    /// A file that couldn't be accepted at load time (over size/count/total). Carried as metadata only — never read into memory and never able to become a valid file.
    struct RejectedFile: Equatable {
        let fileName: String
        let mimeType: String
        let fileSizeBytes: Int
    }

    struct Result {
        var images: [(image: UIImage, fileName: String)] = []
        var files: [AIChatFileAttachment] = []
        /// The first file that didn't fit the budget; capped at one so an exhausted capacity can't flood the strip.
        var rejectedFile: RejectedFile?
        /// More image providers were present than the allowance, so some were dropped without decoding.
        var imagesTruncated = false
    }

    private enum LoadedFile {
        case read(AIChatFileAttachment)
        case rejected(RejectedFile)
    }

    /// Metadata-only probe (no byte reads, so no paste banner) that mirrors `loadAttachments`' per-provider classification, so a "yes" here means the loader will actually find something. Text types are ignored when the pasteboard also holds a string, so copied text/tables paste as text rather than a file.
    static func hasSupportedAttachments(
        in pasteboard: UIPasteboard,
        allowsImages: Bool,
        allowedFileTypes: [UTType]
    ) -> Bool {
        let fileIdentifiers = fileTypesRoutable(from: allowedFileTypes, pasteboardHasStrings: pasteboard.hasStrings).map(\.identifier)
        return pasteboard.itemProviders.contains { provider in
            if allowsImages, provider.canLoadObject(ofClass: UIImage.self) {
                return true
            }
            return fileIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    /// Reads the pasteboard bytes (surfaces the banner) and builds attachments. Images stop decoding at the allowance and files are
    /// size/count-preflighted from metadata against the remaining budget, so a large multi-item paste only ever loads what can be accepted.
    static func loadAttachments(
        from providers: [NSItemProvider],
        allowsImages: Bool,
        allowedFileTypes: [UTType],
        maxImageCount: Int? = nil,
        maxFileSizeBytes: Int? = nil,
        remainingFileCount: Int? = nil,
        remainingTotalFileBytes: Int? = nil,
        pasteboardHasStrings: Bool = false
    ) async -> Result {
        var result = Result()
        let routableFileTypes = fileTypesRoutable(from: allowedFileTypes, pasteboardHasStrings: pasteboardHasStrings)
        var loadedImageCount = 0
        var readFileCount = 0
        var readFileBytes = 0
        var fileCapacityExhausted = false

        for provider in providers {
            if allowsImages, provider.canLoadObject(ofClass: UIImage.self) {
                if let maxImageCount, loadedImageCount >= maxImageCount {
                    result.imagesTruncated = true
                    continue
                }
                if let image = await loadImage(from: provider) {
                    result.images.append((image, provider.suggestedName ?? "image"))
                    loadedImageCount += 1
                }
            } else if let type = routableFileTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                guard !fileCapacityExhausted else { continue }

                let remainingCount = remainingFileCount.map { $0 - readFileCount }
                let remainingBytes = remainingTotalFileBytes.map { $0 - readFileBytes }
                if (remainingCount.map { $0 <= 0 } ?? false) || (remainingBytes.map { $0 <= 0 } ?? false) {
                    fileCapacityExhausted = true
                    recordRejection(RejectedFile(fileName: fileName(for: provider, type: type), mimeType: mimeType(for: type), fileSizeBytes: 0), in: &result)
                    continue
                }

                switch await loadFile(from: provider, type: type, maxFileSizeBytes: maxFileSizeBytes, remainingBytes: remainingBytes) {
                case .read(let file):
                    readFileCount += 1
                    readFileBytes += file.fileSizeBytes
                    result.files.append(file)
                case .rejected(let rejected):
                    recordRejection(rejected, in: &result)
                case nil:
                    break
                }
            }
        }
        return result
    }

    /// Text types route to a file only when the pasteboard has no string — a copied string/table becomes text, a real text file (no string) still attaches.
    private static func fileTypesRoutable(from allowedFileTypes: [UTType], pasteboardHasStrings: Bool) -> [UTType] {
        pasteboardHasStrings ? allowedFileTypes.filter { !$0.conforms(to: .text) } : allowedFileTypes
    }

    private static func recordRejection(_ rejected: RejectedFile, in result: inout Result) {
        if result.rejectedFile == nil {
            result.rejectedFile = rejected
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// Loads via a file representation and preflights per-file size and remaining total bytes from metadata; over-budget files are
    /// returned as rejections (metadata only, never read), so bytes are read only for files that can be accepted.
    private static func loadFile(
        from provider: NSItemProvider,
        type: UTType,
        maxFileSizeBytes: Int?,
        remainingBytes: Int?
    ) async -> LoadedFile? {
        let fileName = fileName(for: provider, type: type)
        let mimeType = mimeType(for: type)

        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                if let fileSize {
                    let overPerFile = maxFileSizeBytes.map { fileSize > $0 } ?? false
                    let overTotal = remainingBytes.map { fileSize > $0 } ?? false
                    if overPerFile || overTotal {
                        continuation.resume(returning: .rejected(RejectedFile(fileName: fileName, mimeType: mimeType, fileSizeBytes: fileSize)))
                        return
                    }
                }

                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: .read(UnifiedToggleInputAttachmentPresenter.makeFileAttachment(data: data, fileName: fileName, mimeType: mimeType)))
            }
        }
    }

    private static func fileName(for provider: NSItemProvider, type: UTType) -> String {
        let baseName = provider.suggestedName ?? "file"
        guard (baseName as NSString).pathExtension.isEmpty, let ext = type.preferredFilenameExtension else { return baseName }
        return "\(baseName).\(ext)"
    }

    private static func mimeType(for type: UTType) -> String {
        type.preferredMIMEType ?? "application/octet-stream"
    }
}
