//
//  CFURLCreateAbsoluteURLWithBytesSwapper.swift
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

//
// Dynamic GOT-patching swapper, identical in technique to CxaThrowSwapper.swift.
//
// installCFURLSwapper()  — registers a _dyld_register_func_for_add_image callback that
//   walks every loaded Mach-O image for the `CFURLCreateAbsoluteURLWithBytes` indirect-
//   symbol-table entry and replaces it with the hook below.  Images loaded after the
//   call are patched automatically via the same callback.
//
// uninstallCFURLSwapper() — restores the saved original function pointer in every
//   currently loaded image.  Future images are not patched because the callback checks
//   _cfURLHookInstalled before acting.
//

import Common
import CoreFoundation
import Foundation
import MachO
import os.log

// MARK: - Types

private typealias CFURLCreateFn = @convention(c) (
    CFAllocator?, UnsafePointer<UInt8>?, CFIndex, CFStringEncoding, CFURL?, Bool
) -> CFURL?

// MARK: - Associated-object key

/// Byte-range storage used as the associated-object key.
/// Its address is registered into `cfURLFragmentByteRangeAssociationKey` (in BSK Common)
/// during install so URLExtension.swift can read it without a hard dependency on this file.
private nonisolated(unsafe) var _cfURLFragmentKeyStorage: Int8 = 0

// MARK: - Module-level state

private nonisolated(unsafe) var _cfURLOriginalFn: CFURLCreateFn?
private nonisolated(unsafe) var _cfURLOriginalsByImage = [UnsafeRawPointer: UnsafeRawPointer]()
private nonisolated(unsafe) var _cfURLHookInstalled = false
private nonisolated(unsafe) var _cfURLCallbackRegistered = false

private let _cfURLLog = OSLog(subsystem: "com.duckduckgo.navigation", category: "CFURLSwapper")

// MARK: - Hook

/// `@convention(c)` hook installed in the GOT of every loaded image.
/// Must not capture any local variables – all state is module-level.
private nonisolated(unsafe) let _cfURLHook: CFURLCreateFn = { allocator, bytes, length, encoding, baseURL, useCompatibilityMode in
    var original = _cfURLOriginalFn
    if original == nil {
        // Safety net during an uninstall race: bypass the (already-restoring) GOT via dlsym.
        // RTLD_DEFAULT == (void *)-2 on Apple platforms.
        original = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CFURLCreateAbsoluteURLWithBytes")
            .map { unsafeBitCast($0, to: CFURLCreateFn.self) }
    }

    let result = original?(allocator, bytes, length, encoding, baseURL, useCompatibilityMode)

    if let result, let bytes, length > 0 {
        // Skip re-scanning if this URL has already been processed by the hook.
        let url = result as URL
        guard !url.isOpaqueFragmentScanned else { return result }

        // Use libc memchr (SIMD-vectorised on ARM64/x86) instead of Swift range iteration.
        // First locate ':' — required for an opaque URL — then verify it is not followed
        // by '//' (which would make it hierarchical), then search only the suffix for '#'.
        let len = Int(length)
        let rawBase = UnsafeRawPointer(bytes)
        if let colonRaw = memchr(rawBase, Int32(UInt8(ascii: ":")), len) {
            let colonOff = rawBase.distance(to: colonRaw)          // offset of ':'
            let afterColon = colonOff + 1
            // Opaque: ':' is NOT followed by '//'
            let isOpaque = !(afterColon + 1 < len &&
                             bytes[afterColon]     == UInt8(ascii: "/") &&
                             bytes[afterColon + 1] == UInt8(ascii: "/"))
            if isOpaque {
                let searchBase = rawBase.advanced(by: afterColon)
                let searchLen  = len - afterColon
                if let hashRaw = memchr(searchBase, Int32(UInt8(ascii: "#")), searchLen) {
                    let hashOff = afterColon + searchBase.distance(to: hashRaw)

                    let range   = NSRange(location: hashOff, length: len - hashOff)
                    url.opaqueFragmentAnnotation = range
                } else {
                    // Opaque URL fully scanned — no '#' found.
                    // Store NSNull sentinel so this URL is not re-scanned on future hook calls.
                    url.opaqueFragmentAnnotation = nil
                }
            }
        }
    }

    return result
}

// MARK: - dyld callback

private func _cfURLProcessMachHeader(_ header: UnsafePointer<mach_header>?, _ slide: Int) {
    guard _cfURLHookInstalled, let header else { return }

    var dlInfo = Dl_info()
    let imageName = dladdr(UnsafeRawPointer(header), &dlInfo) != 0 && dlInfo.dli_fname != nil
        ? (String(cString: dlInfo.dli_fname) as NSString).lastPathComponent as String
        : String(format: "0x%lx", UInt(bitPattern: header))
    guard _cfURLShouldPatchImage(named: imageName) else { return }
    let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
    guard let imageMap = ImageMap(header: header64, slide: slide) else {
        os_log(.debug, log: _cfURLLog, "  ImageMap init failed for %{public}@", imageName)
        return
    }
    let replacement = unsafeBitCast(_cfURLHook, to: UnsafeRawPointer.self)
    do {
        let patched = try imageMap.rebindSymbol("CFURLCreateAbsoluteURLWithBytes",
                                                slide: slide,
                                                to: replacement,
                                                savingOriginalTo: &_cfURLOriginalsByImage,
                                                patchDyldCacheStubTargets: true)
        guard patched else {
            os_log(.debug, log: _cfURLLog, "  no CFURLCreateAbsoluteURLWithBytes import slot in %{public}@", imageName)
            return
        }

        os_log(.debug, log: _cfURLLog, "  patched CFURLCreateAbsoluteURLWithBytes import slot in %{public}@", imageName)
    } catch {
        os_log(.error, log: _cfURLLog, "rebind failed: %{public}@", error.localizedDescription)
    }
}

private func _cfURLShouldPatchImage(named imageName: String) -> Bool {
    imageName == "WebKit"
}

// MARK: - Install / Uninstall

func installCFURLSwapper() {
    guard !_cfURLHookInstalled else { return }
    _cfURLOriginalFn = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CFURLCreateAbsoluteURLWithBytes")
        .map { unsafeBitCast($0, to: CFURLCreateFn.self) }
    _cfURLHookInstalled = true

    // Register the association key so URLExtension.swift (in BSK Common) can find it
    // without a compile-time dependency on this macOS-only file.
    cfURLFragmentByteRangeAssociationKey = UnsafeRawPointer(&_cfURLFragmentKeyStorage)

    if !_cfURLCallbackRegistered {
        _cfURLCallbackRegistered = true
        // Registers callback AND immediately invokes it for every already-loaded image.
        _dyld_register_func_for_add_image(_cfURLProcessMachHeader)
    } else {
        // Callback already registered but was skipping while !_cfURLHookInstalled.
        // Re-patch all currently loaded images manually.
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let header = _dyld_get_image_header(i) else { continue }
            _cfURLProcessMachHeader(header, _dyld_get_image_vmaddr_slide(i))
        }
    }

    os_log(.info, log: _cfURLLog, "CFURLCreateAbsoluteURLWithBytes swapper installed")
}

func uninstallCFURLSwapper() {
    guard _cfURLHookInstalled else { return }
    _cfURLHookInstalled = false

    guard let original = _cfURLOriginalFn else { return }
    let originalPtr = unsafeBitCast(original, to: UnsafeRawPointer.self)
    var discardedOriginals = [UnsafeRawPointer: UnsafeRawPointer]()

    let count = _dyld_image_count()
    for i in 0..<count {
        guard let header = _dyld_get_image_header(i) else { continue }
        let imageName = _dyld_get_image_name(i)
            .map { (String(cString: $0) as NSString).lastPathComponent as String } ?? ""
        guard _cfURLShouldPatchImage(named: imageName) else { continue }

        let slide = _dyld_get_image_vmaddr_slide(i)
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let imageMap = ImageMap(header: header64, slide: slide) else { continue }
        do {
            try imageMap.rebindSymbol("CFURLCreateAbsoluteURLWithBytes",
                                      slide: slide,
                                      to: originalPtr,
                                      savingOriginalTo: &discardedOriginals,
                                      patchDyldCacheStubTargets: true)
        } catch {
            os_log(.error, log: _cfURLLog, "restore failed: %{public}@", error.localizedDescription)
        }
    }

    _cfURLOriginalFn = nil
    _cfURLOriginalsByImage.removeAll()
    os_log(.info, log: _cfURLLog, "CFURLCreateAbsoluteURLWithBytes swapper uninstalled")
}
