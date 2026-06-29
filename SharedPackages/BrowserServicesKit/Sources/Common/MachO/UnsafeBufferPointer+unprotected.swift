//
//  UnsafeBufferPointer+unprotected.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import FoundationExtensions
import Foundation
import MachO
import os.log

extension UnsafeBufferPointer {

    struct MemoryProtectionFailure: LocalizedError {
        let bufferDescr: String
        let kernReturn: kern_return_t

        var errorDescription: String? {
            String("vm_protect failed for \(bufferDescr): kr=\(kernReturn)")
        }
    }

    /// Temporarily makes the buffer's pages writable (if needed) using the Mach `vm_protect`
    /// API with `VM_PROT_COPY`, which correctly handles `__DATA_CONST` shared-mapping pages
    /// by triggering copy-on-write before the write.  `mprotect` (POSIX) cannot do this.
    ///
    /// The address range is rounded to page boundaries as required by `vm_protect`.
    /// Protection is restored to the original value in a `defer` block.
    ///
    /// - Returns: Generic callback result.
    /// - Throws: `MemoryProtectionFailure` if `vm_protect` fails.
    func withTemporaryUnprotectedMemory<Result>(_ body: (_ pointer: UnsafeMutableBufferPointer<Self.Element>) throws -> Result) throws -> Result {
        guard let base = baseAddress else {
            return try body(UnsafeMutableBufferPointer(mutating: self))
        }

        let originalProtection = try vm_region_basic_info_data_64_t(base).protection
        let needsUnprotect = originalProtection & (VM_PROT_WRITE | VM_PROT_READ) != (VM_PROT_WRITE | VM_PROT_READ)

        if needsUnprotect {
            let (pageBase, pageLength) = pageAlignedRange(for: base, byteCount: count * MemoryLayout<Element>.size)
            // VM_PROT_COPY triggers copy-on-write, which is required for __DATA_CONST pages
            // that are initially mapped read-only from a shared file-backed region.
            let kr = vm_protect(mach_task_self_, pageBase, pageLength, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)
            guard kr == KERN_SUCCESS else { throw MemoryProtectionFailure(bufferDescr: self.debugDescription, kernReturn: kr) }

            defer {
                let kr = vm_protect(mach_task_self_, pageBase, pageLength, 0, originalProtection)
                if kr != KERN_SUCCESS {
                    Logger.general.error("vm_protect restore failed for \(self.debugDescription, privacy: .public): kr=\(kr, privacy: .public)")
                }
            }

            return try body(UnsafeMutableBufferPointer(mutating: self))
        }

        return try body(UnsafeMutableBufferPointer(mutating: self))
    }

}

private func pageAlignedRange(for base: UnsafeRawPointer, byteCount: Int) -> (vm_address_t, vm_size_t) {
    let page = UInt(vm_page_size)
    let start = UInt(bitPattern: base)
    let end = start + UInt(byteCount)
    let alignedStart = start & ~(page - 1)
    let alignedEnd = (end + page - 1) & ~(page - 1)
    return (vm_address_t(alignedStart), vm_size_t(alignedEnd - alignedStart))
}
