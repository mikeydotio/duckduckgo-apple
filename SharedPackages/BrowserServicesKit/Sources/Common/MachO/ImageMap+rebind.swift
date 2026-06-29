//
//  ImageMap+rebind.swift
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
//
// The indirect-symbol-table GOT-patching technique is inspired by facebook/fishhook
// https://github.com/facebook/fishhook
//
// Copyright (c) 2013, Facebook, Inc.
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//   * Neither the name Facebook nor the names of its contributors may be used to
//     endorse or promote products derived from this software without specific
//     prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation
import MachO
import MachORebindingSupport
import os.log

private let indicesToSkip = [UInt32(INDIRECT_SYMBOL_ABS), INDIRECT_SYMBOL_LOCAL, INDIRECT_SYMBOL_LOCAL | UInt32(INDIRECT_SYMBOL_ABS)]
private let rebindLog = OSLog(subsystem: "com.duckduckgo", category: "ImageMap.rebind")

private let chainedImport = UInt32(1)
private let chainedImportAddend = UInt32(2)
private let chainedImportAddend64 = UInt32(3)

private let chainedPtrArm64e = UInt16(1)
private let chainedPtr64 = UInt16(2)
private let chainedPtr64Offset = UInt16(6)
private let chainedPtrArm64eUserland = UInt16(9)
private let chainedPtrArm64eUserland24 = UInt16(12)

private let chainedPtrStartNone = UInt16(0xffff)
private let chainedPtrStartMulti = UInt16(0x8000)

public extension ImageMap {

    /// Replace all lazy and non-lazy GOT entries for `symbolName` in this image with `replacement`.
    ///
    /// The first time a slot is patched, the original pointer is saved into `originals` keyed by the
    /// image base address (from `dladdr`), so the caller can restore it later via a second call with
    /// the saved pointer as `replacement`.
    ///
    /// - Parameters:
    ///   - targetSymbol: Bare C symbol name without a leading underscore (e.g. `"__cxa_throw"`).
    ///   - slide: ASLR slide for this image (as provided by `_dyld_register_func_for_add_image`).
    ///   - replacement: Function pointer to install in the GOT slot.
    ///   - originals: Caller-owned dictionary; updated with `imageBase → originalPointer` on first patch.
    @discardableResult
    func rebindSymbol(_ targetSymbol: String,
                      slide: Int,
                      to replacement: UnsafeRawPointer,
                      savingOriginalTo originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                      patchDyldCacheStubTargets: Bool = false) throws -> Bool {
        var dlInfo = Dl_info()
        let imageName: String = {
            guard dladdr(UnsafeRawPointer(header), &dlInfo) != 0, let fname = dlInfo.dli_fname else { return nil }
            return (String(cString: fname) as NSString).lastPathComponent as String
        }() ?? "<unknown>"

        os_log(.debug, log: rebindLog, "rebindSymbol in %{public}@", imageName)
        var didRebind = false

        func processSegment(_ segment: UnsafePointer<segment_command_64>?) throws {
            guard let segment else { return }
            for section in segment.sections.baseAddress! ..< segment.sections.baseAddress!.advanced(by: segment.sections.count) {
                guard let indirectSymtab else {
                    os_log(.debug, log: rebindLog, "    no indirectSymtab")
                    continue
                }

                if patchDyldCacheStubTargets {
                    didRebind = try rebindSymbolStubTargetSlot(section.pointee,
                                                               slide: slide,
                                                               indirectSymtab: indirectSymtab,
                                                               targetSymbol: targetSymbol,
                                                               replacement: replacement,
                                                               originals: &originals,
                                                               imageName: imageName) || didRebind

                    didRebind = try rebindRegularIndirectPointerSection(section.pointee,
                                                                        slide: slide,
                                                                        indirectSymtab: indirectSymtab,
                                                                        targetSymbol: targetSymbol,
                                                                        replacement: replacement,
                                                                        originals: &originals,
                                                                        imageName: imageName) || didRebind
                }

                guard [S_LAZY_SYMBOL_POINTERS, S_NON_LAZY_SYMBOL_POINTERS].contains(section.pointee.type) else {
                    continue
                }

                try section.pointee.indirectSymbolBindings(slide: slide)?.withTemporaryUnprotectedMemory { bindings in
                    guard let indices = section.pointee.indirectSymbolIndices(indirectSymtab: indirectSymtab) else {
                        os_log(.debug, log: rebindLog, "    no indirectSymbolIndices")
                        return
                    }
                    for i in 0 ..< section.pointee.count where indices.indices.contains(i) && bindings.indices.contains(i) {
                        let symtabIndex = indices[i]
                        guard !indicesToSkip.contains(symtabIndex) else { continue }
                        guard let name = symbolName(at: Int(symtabIndex)),
                              name[0] != 0, name[1] != 0 else { continue }
                        os_log(.debug, log: rebindLog, "    [%u] '%{public}@'", i, String(cString: name))
                        guard strcmp(name.advanced(by: 1), targetSymbol) == 0 else { continue }

                        os_log(.debug, log: rebindLog, "    MATCH → patching slot[%u] old=0x%lx new=0x%lx", i, UInt(bitPattern: bindings[i]), UInt(bitPattern: replacement))
                        let imageBase = UnsafeRawPointer(try Dl_info(section).dli_fbase)!
                        if originals[imageBase] == nil {
                            originals[imageBase] = bindings[i]
                        }
                        bindings[i] = replacement
                        didRebind = true
                        break
                    }
                }
            }
        }

        for segment in segments {
            try processSegment(segment)
        }

        if patchDyldCacheStubTargets {
            didRebind = try rebindChainedFixups(targetSymbol,
                                                replacement: replacement,
                                                originals: &originals,
                                                imageName: imageName) || didRebind
        }

        if !didRebind {
            os_log(.debug, log: rebindLog, "  no %{public}@ import slot found in %{public}@", targetSymbol, imageName)
        }

        return didRebind
    }

}

private extension ImageMap {

    func rebindSymbolStubTargetSlot(_ section: section_64,
                                    slide: Int,
                                    indirectSymtab: UnsafeBufferPointer<UInt32>,
                                    targetSymbol: String,
                                    replacement: UnsafeRawPointer,
                                    originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                                    imageName: String) throws -> Bool {
        guard section.type == S_SYMBOL_STUBS,
              section.reserved2 >= MemoryLayout<UInt32>.size,
              let indices = indirectSymbolIndices(for: section, count: symbolStubCount(in: section), indirectSymtab: indirectSymtab),
              let stubBase = UnsafeRawPointer(bitPattern: UInt(section.addr) &+ UInt(bitPattern: slide)) else {
            return false
        }

        var didRebind = false
        for index in indices.indices {
            let symtabIndex = indices[index]
            guard !indicesToSkip.contains(symtabIndex),
                  let name = symbolName(at: Int(symtabIndex)),
                  matchesSymbolName(name, targetSymbol: targetSymbol) else { continue }

            let stub = stubBase.advanced(by: index * Int(section.reserved2))
            guard let targetSlot = decodeArm64StubLoadAddress(stub: stub) else {
                os_log(.debug, log: rebindLog, "    STUB MATCH %{public}@ in %{public}@[%d] but failed to decode target slot",
                       targetSymbol, section.name, index)
                continue
            }

            let oldValue = targetSlot.pointee
            guard let signedReplacement = UnsafeRawPointer(BSKSignInstructionPointer(replacement, UInt(bitPattern: targetSlot))) else { continue }
            os_log(.debug, log: rebindLog, "    STUB MATCH %{public}@ %{public}@[%d] targetSlot=0x%lx old=0x%lx new=0x%lx signed=0x%lx",
                   targetSymbol,
                   section.name,
                   index,
                   UInt(bitPattern: targetSlot),
                   UInt(bitPattern: oldValue),
                   UInt(bitPattern: replacement),
                   UInt(bitPattern: signedReplacement))

            let slot = UnsafeBufferPointer(start: UnsafePointer(targetSlot), count: 1)
            try slot.withTemporaryUnprotectedMemory { writable in
                let imageBase = UnsafeRawPointer(header)
                if originals[imageBase] == nil {
                    originals[imageBase] = oldValue
                }
                writable[0] = signedReplacement
                didRebind = true
            }
        }

        if didRebind {
            os_log(.debug, log: rebindLog, "  patched %{public}@ auth stub target slot(s) in %{public}@", targetSymbol, imageName)
        }
        return didRebind
    }

    func rebindRegularIndirectPointerSection(_ section: section_64,
                                             slide: Int,
                                             indirectSymtab: UnsafeBufferPointer<UInt32>,
                                             targetSymbol: String,
                                             replacement: UnsafeRawPointer,
                                             originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                                             imageName: String) throws -> Bool {
        guard section.type == S_REGULAR,
              ["__got", "__auth_got"].contains(section.name),
              let indices = indirectSymbolIndices(for: section, count: section.count, indirectSymtab: indirectSymtab),
              let sectionPointer = UnsafeRawPointer(bitPattern: UInt(section.addr) &+ UInt(bitPattern: slide)) else {
            return false
        }

        let bindings = UnsafeBufferPointer(start: sectionPointer.assumingMemoryBound(to: UnsafeRawPointer.self),
                                           count: indices.count)
        var didRebind = false

        try bindings.withTemporaryUnprotectedMemory { writable in
            for index in indices.indices where writable.indices.contains(index) {
                let symtabIndex = indices[index]
                guard !indicesToSkip.contains(symtabIndex),
                      let name = symbolName(at: Int(symtabIndex)),
                      matchesSymbolName(name, targetSymbol: targetSymbol) else { continue }

                let oldValue = writable[index]
                let replacementToWrite: UnsafeRawPointer
                if section.name == "__auth_got" {
                    guard let signedReplacement = UnsafeRawPointer(BSKSignInstructionPointer(replacement, UInt(bitPattern: writable.baseAddress!.advanced(by: index)))) else { continue }
                    replacementToWrite = signedReplacement
                } else {
                    replacementToWrite = replacement
                }

                os_log(.debug, log: rebindLog, "    REGULAR INDIRECT MATCH %{public}@ %{public}@[%d] old=0x%lx new=0x%lx",
                       targetSymbol,
                       section.name,
                       index,
                       UInt(bitPattern: oldValue),
                       UInt(bitPattern: replacementToWrite))

                let imageBase = UnsafeRawPointer(header)
                if originals[imageBase] == nil {
                    let originalValue: UnsafeRawPointer?
                    if UInt(bitPattern: oldValue) != 0 {
                        originalValue = oldValue
                    } else {
                        originalValue = dlsym(UnsafeMutableRawPointer(bitPattern: -2), targetSymbol).map(UnsafeRawPointer.init)
                    }
                    if let originalValue {
                        originals[imageBase] = originalValue
                    }
                }
                writable[index] = replacementToWrite
                didRebind = true
            }
        }

        if didRebind {
            os_log(.debug, log: rebindLog, "  patched %{public}@ regular indirect pointer(s) in %{public}@", targetSymbol, imageName)
        }
        return didRebind
    }

    struct ChainedStartsInSegment {
        let pageSize: UInt16
        let pointerFormat: UInt16
        let segmentOffset: UInt64
        let pageCount: UInt16
        let pageStarts: UnsafePointer<UInt16>
    }

    func rebindChainedFixups(_ targetSymbol: String,
                             replacement: UnsafeRawPointer,
                             originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                             imageName: String) throws -> Bool {
        guard let chainedFixupsCmd else { return false }

        let fixupsBase = linkeditBase.advanced(by: Int(chainedFixupsCmd.dataoff))
        let header = fixupsBase.assumingMemoryBound(to: dyld_chained_fixups_header.self).pointee
        guard header.symbols_format == 0 else {
            os_log(.debug, log: rebindLog, "  chained fixups use unsupported compressed symbols format=%u", header.symbols_format)
            return false
        }

        let importOrdinals = chainedImportOrdinals(named: targetSymbol,
                                                   fixupsBase: fixupsBase,
                                                   fixupsHeader: header)
        guard !importOrdinals.isEmpty else {
            os_log(.debug, log: rebindLog, "  chained fixups do not import %{public}@ in %{public}@", targetSymbol, imageName)
            return false
        }

        os_log(.debug, log: rebindLog, "  chained fixups import %{public}@ ordinals=%{public}@", targetSymbol, String(describing: importOrdinals))

        let startsBase = fixupsBase.advanced(by: Int(header.starts_offset))
        let segmentCount = Int(startsBase.assumingMemoryBound(to: UInt32.self).pointee)
        let segmentInfoOffsets = startsBase.advanced(by: MemoryLayout<UInt32>.size).assumingMemoryBound(to: UInt32.self)
        var didRebind = false

        for segmentIndex in 0..<segmentCount {
            let segmentInfoOffset = segmentInfoOffsets.advanced(by: segmentIndex).pointee
            guard segmentInfoOffset != 0,
                  let starts = chainedStartsInSegment(at: startsBase.advanced(by: Int(segmentInfoOffset))) else { continue }

            os_log(.debug, log: rebindLog, "  chained segment[%d] format=%u pages=%u", segmentIndex, starts.pointerFormat, starts.pageCount)

            for pageIndex in 0..<Int(starts.pageCount) {
                let pageStart = starts.pageStarts.advanced(by: pageIndex).pointee
                guard pageStart != chainedPtrStartNone else { continue }
                guard pageStart & chainedPtrStartMulti == 0 else {
                    os_log(.debug, log: rebindLog, "    chained multi-start page unsupported segment=%d page=%d", segmentIndex, pageIndex)
                    continue
                }

                didRebind = try walkChain(starts: starts,
                                          pageIndex: pageIndex,
                                          pageStart: pageStart,
                                          importOrdinals: importOrdinals,
                                          replacement: replacement,
                                          originals: &originals,
                                          imageName: imageName) || didRebind
            }
        }

        return didRebind
    }

    func chainedImportOrdinals(named targetSymbol: String,
                               fixupsBase: UnsafeRawPointer,
                               fixupsHeader: dyld_chained_fixups_header) -> Set<Int> {
        let importsBase = fixupsBase.advanced(by: Int(fixupsHeader.imports_offset))
        let symbolsBase = fixupsBase.advanced(by: Int(fixupsHeader.symbols_offset))
        let targetNames = ["_\(targetSymbol)", targetSymbol]
        var ordinals = Set<Int>()

        for ordinal in 0..<Int(fixupsHeader.imports_count) {
            let nameOffset: UInt32?
            switch fixupsHeader.imports_format {
            case chainedImport:
                let raw = importsBase.advanced(by: ordinal * MemoryLayout<UInt32>.size).assumingMemoryBound(to: UInt32.self).pointee
                nameOffset = raw >> 9
            case chainedImportAddend:
                let raw = importsBase.advanced(by: ordinal * (MemoryLayout<UInt32>.size + MemoryLayout<Int32>.size)).assumingMemoryBound(to: UInt32.self).pointee
                nameOffset = raw >> 9
            case chainedImportAddend64:
                let raw = importsBase.advanced(by: ordinal * (MemoryLayout<UInt64>.size + MemoryLayout<UInt64>.size)).assumingMemoryBound(to: UInt64.self).pointee
                nameOffset = UInt32(raw >> 32)
            default:
                os_log(.debug, log: rebindLog, "  unsupported chained imports format=%u", fixupsHeader.imports_format)
                return []
            }

            guard let nameOffset else { continue }
            let name = String(cString: symbolsBase.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self))
            if targetNames.contains(name) {
                ordinals.insert(ordinal)
            }
        }

        return ordinals
    }

    func chainedStartsInSegment(at startsBase: UnsafeRawPointer) -> ChainedStartsInSegment? {
        let pageSize = startsBase.advanced(by: 4).assumingMemoryBound(to: UInt16.self).pointee
        let pointerFormat = startsBase.advanced(by: 6).assumingMemoryBound(to: UInt16.self).pointee
        let segmentOffset = startsBase.advanced(by: 8).assumingMemoryBound(to: UInt64.self).pointee
        let pageCount = startsBase.advanced(by: 20).assumingMemoryBound(to: UInt16.self).pointee
        let pageStarts = startsBase.advanced(by: 22).assumingMemoryBound(to: UInt16.self)

        guard pageSize != 0 else { return nil }
        return ChainedStartsInSegment(pageSize: pageSize,
                                      pointerFormat: pointerFormat,
                                      segmentOffset: segmentOffset,
                                      pageCount: pageCount,
                                      pageStarts: pageStarts)
    }

    func walkChain(starts: ChainedStartsInSegment,
                   pageIndex: Int,
                   pageStart: UInt16,
                   importOrdinals: Set<Int>,
                   replacement: UnsafeRawPointer,
                   originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                   imageName: String) throws -> Bool {
        var chainOffset = UInt64(pageStart)
        var didRebind = false
        var guardCount = 0

        while true {
            guardCount += 1
            guard guardCount < 100_000 else {
                os_log(.error, log: rebindLog, "    chained fixups loop guard tripped in %{public}@", imageName)
                break
            }

            let location = UnsafeRawPointer(header)
                .advanced(by: Int(starts.segmentOffset))
                .advanced(by: pageIndex * Int(starts.pageSize))
                .advanced(by: Int(chainOffset))
            let rawPointer = location.assumingMemoryBound(to: UInt64.self)
            let raw = rawPointer.pointee

            let decoded = decodeChainedBind(raw, pointerFormat: starts.pointerFormat)
            if let decoded, importOrdinals.contains(decoded.ordinal) {
                os_log(.debug, log: rebindLog, "    CHAIN MATCH ordinal=%d old=0x%lx new=0x%lx", decoded.ordinal, raw, UInt(bitPattern: replacement))
                try UnsafeBufferPointer(start: rawPointer, count: 1).withTemporaryUnprotectedMemory { writable in
                    let imageBase = UnsafeRawPointer(header)
                    if originals[imageBase] == nil {
                        originals[imageBase] = UnsafeRawPointer(bitPattern: UInt(raw))
                    }
                    writable[0] = UInt64(UInt(bitPattern: replacement))
                    didRebind = true
                }
            }

            let next = decoded?.next ?? decodeChainedNext(raw, pointerFormat: starts.pointerFormat)
            guard next != 0 else { break }
            chainOffset += UInt64(next) * UInt64(chainedStride(for: starts.pointerFormat))
        }

        return didRebind
    }

    func decodeChainedBind(_ raw: UInt64, pointerFormat: UInt16) -> (ordinal: Int, next: UInt16)? {
        switch pointerFormat {
        case chainedPtrArm64e, chainedPtrArm64eUserland:
            guard ((raw >> 62) & 1) == 1 else { return nil }
            return (Int(raw & 0xffff), UInt16((raw >> 51) & 0x7ff))
        case chainedPtrArm64eUserland24:
            guard ((raw >> 62) & 1) == 1 else { return nil }
            return (Int(raw & 0x00ff_ffff), UInt16((raw >> 51) & 0x7ff))
        case chainedPtr64, chainedPtr64Offset:
            guard ((raw >> 63) & 1) == 1 else { return nil }
            return (Int(raw & 0x00ff_ffff), UInt16((raw >> 51) & 0xfff))
        default:
            return nil
        }
    }

    func decodeChainedNext(_ raw: UInt64, pointerFormat: UInt16) -> UInt16 {
        switch pointerFormat {
        case chainedPtrArm64e, chainedPtrArm64eUserland, chainedPtrArm64eUserland24:
            UInt16((raw >> 51) & 0x7ff)
        case chainedPtr64, chainedPtr64Offset:
            UInt16((raw >> 51) & 0xfff)
        default:
            0
        }
    }

    func chainedStride(for pointerFormat: UInt16) -> UInt16 {
        switch pointerFormat {
        case chainedPtr64, chainedPtr64Offset:
            4
        default:
            8
        }
    }

    func rebindResolvedPointers(_ targetSymbol: String,
                                slide: Int,
                                replacement: UnsafeRawPointer,
                                originals: inout [UnsafeRawPointer: UnsafeRawPointer],
                                imageName: String) throws -> Bool {
        guard let target = dlsym(UnsafeMutableRawPointer(bitPattern: -2), targetSymbol) else { return false }
        let targetBits = UInt(bitPattern: target)
        var didRebind = false

        for segment in segments where segment.isDataLikeSegment {
            for section in segment.sections where section.size >= UInt64(MemoryLayout<UnsafeRawPointer>.size) {
                let count = Int(section.size / UInt64(MemoryLayout<UnsafeRawPointer>.size))
                guard count > 0,
                      let sectionPointer = UnsafeRawPointer(bitPattern: UInt(section.addr) &+ UInt(bitPattern: slide)) else { continue }

                let bindings = UnsafeBufferPointer(start: sectionPointer.assumingMemoryBound(to: UnsafeRawPointer.self),
                                                   count: count)
                try bindings.withTemporaryUnprotectedMemory { writable in
                    for index in writable.indices where UInt(bitPattern: writable[index]) == targetBits {
                        os_log(.debug, log: rebindLog, "    RESOLVED MATCH %{public}@ section=%{public}@[%d] old=0x%lx new=0x%lx",
                               targetSymbol,
                               section.name,
                               index,
                               UInt(bitPattern: writable[index]),
                               UInt(bitPattern: replacement))
                        let imageBase = UnsafeRawPointer(header)
                        if originals[imageBase] == nil {
                            originals[imageBase] = writable[index]
                        }
                        writable[index] = replacement
                        didRebind = true
                    }
                }
            }
        }

        if didRebind {
            os_log(.debug, log: rebindLog, "  patched resolved %{public}@ pointer(s) in %{public}@", targetSymbol, imageName)
        }
        return didRebind
    }

}

private func matchesSymbolName(_ symbolName: UnsafePointer<CChar>, targetSymbol: String) -> Bool {
    guard symbolName[0] != 0 else { return false }
    if symbolName[0] == CChar(UInt8(ascii: "_")) {
        return strcmp(symbolName.advanced(by: 1), targetSymbol) == 0
    }
    return strcmp(symbolName, targetSymbol) == 0
}

private func symbolStubCount(in section: section_64) -> Int {
    guard section.reserved2 > 0 else { return 0 }
    return Int(section.size / UInt64(section.reserved2))
}

private func indirectSymbolIndices(for section: section_64,
                                   count requestedCount: Int,
                                   indirectSymtab: UnsafeBufferPointer<UInt32>) -> UnsafeBufferPointer<UInt32>? {
    guard requestedCount > 0, Int(section.reserved1) < indirectSymtab.count else { return nil }
    let count = min(requestedCount, indirectSymtab.count - Int(section.reserved1))
    guard count > 0 else { return nil }
    return UnsafeBufferPointer(start: indirectSymtab.baseAddress!.advanced(by: Int(section.reserved1)), count: count)
}

private func decodeArm64StubLoadAddress(stub: UnsafeRawPointer) -> UnsafeMutablePointer<UnsafeRawPointer>? {
    let instructions = stub.assumingMemoryBound(to: UInt32.self)
    let adrp = instructions[0]
    let add = instructions[1]
    let ldr = instructions[2]

    let immlo = (adrp >> 29) & 0x3
    let immhi = (adrp >> 5) & 0x7ffff
    let adrpImmediate = signExtend((immhi << 2) | immlo, bitCount: 21) << 12
    let page = Int64(UInt(bitPattern: stub) & ~UInt(0xfff))

    var addImmediate = Int64((add >> 10) & 0xfff)
    if ((add >> 22) & 0x3) == 1 {
        addImmediate <<= 12
    }

    let ldrImmediate = Int64(((ldr >> 10) & 0xfff) << 3)
    let address = page + adrpImmediate + addImmediate + ldrImmediate
    guard address > 0 else { return nil }
    return UnsafeMutableRawPointer(bitPattern: UInt(address))?.assumingMemoryBound(to: UnsafeRawPointer.self)
}

private func signExtend(_ value: UInt32, bitCount: Int) -> Int64 {
    let shift = 64 - bitCount
    return Int64(bitPattern: UInt64(value) << UInt64(shift)) >> Int64(shift)
}

private extension UnsafePointer where Pointee == segment_command_64 {

    var isDataLikeSegment: Bool {
        switch segname {
        case SEG_DATA, "__DATA_CONST", "__AUTH", "__AUTH_CONST", "__DATA_DIRTY":
            return true
        default:
            return false
        }
    }

}

private extension section_64 {

    var name: String {
        withUnsafeBytes(of: sectname) { String(bytes: $0.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "?" }
    }

}
